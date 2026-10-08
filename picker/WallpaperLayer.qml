import QtQuick
import Quickshell
import Quickshell.Wayland
import "../logic/ThemeColors.js" as Colors
import qs.common
import qs.services

/**
 * berri's own desktop background (28): one PanelWindow per monitor, on the
 * Wayland background layer, below everything else and taking no input.
 * Draws Wallpapers.wallpaperFor(screen.name), or a solid
 * Theme.darkerBackground when that monitor has no wallpaper
 * assigned.
 *
 * A wallpaper-only change (same theme: a new assignment, or removing one)
 * cross-fades after the incoming image reports Ready. A failed load keeps
 * the current image. Each screen ignores loads from older choices.
 *
 * A theme switch (Theme.wallpaperTransition, 28a) instead runs one of five
 * picked transitions in a fragment shader (shaders/transition.frag), from
 * the old frame (old image or old solid color) to the new one, in device
 * pixels for this screen. The shader effect exists only while that runs;
 * once it ends the plain image/solid color shows again and nothing keeps
 * repainting.
 */
Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: layer
        required property var modelData

        screen: modelData
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "berri-wallpaper"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors { top: true; left: true; right: true; bottom: true }

        // No input at all, ever: an empty region is a zero-area mask, so
        // every click passes straight through to whatever is above us.
        mask: Region {}

        readonly property string wallpaperPath: Wallpapers.wallpaperFor(modelData.name)
        // Theme.transitioning is true for the single statement that changes
        // currentKey as part of a transitioned apply(); skip our own
        // cross-fade then, since the shader transition below is about to
        // run instead. A plain wallpaper-only change (same theme) still
        // cross-fades as before.
        onWallpaperPathChanged: if (!Theme.transitioning) layer.show(layer.wallpaperPath)

        Component.onCompleted: layer.show(layer.wallpaperPath)

        /** Solid fallback color, underneath both images. */
        Rectangle {
            anchors.fill: parent
            color: Theme.darkerBackground
        }

        Image {
            id: imageA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: false
            sourceSize.width: layer.width * modelData.devicePixelRatio
            sourceSize.height: layer.height * modelData.devicePixelRatio
            opacity: 0
            Behavior on opacity { id: behaviorA; StandardMotion { duration: 450 } }
            onOpacityChanged: layer.freeHiddenImage(imageA)
        }

        Image {
            id: imageB
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: false
            sourceSize.width: layer.width * modelData.devicePixelRatio
            sourceSize.height: layer.height * modelData.devicePixelRatio
            opacity: 0
            Behavior on opacity { id: behaviorB; StandardMotion { duration: 450 } }
            onOpacityChanged: layer.freeHiddenImage(imageB)
        }

        /** true when imageA is the currently-visible layer (imageB is the standby one). */
        property bool aVisible: false

        /** The image that holds the current wallpaper. */
        readonly property Item screenImage: layer.aVisible ? imageA : imageB
        /** The image available for the next wallpaper. */
        readonly property Item hiddenImage: layer.aVisible ? imageB : imageA

        /** Absolute path currently shown (matches whichever Image is visible), or "" for the solid color. Tracked separately from wallpaperPath so a transition still knows its "old frame" after Theme.currentKey has already moved on to the new theme. */
        property string currentPath: ""

        /** The newest load requested for this screen. */
        property int requestNumber: 0
        /** The callback for the pending wallpaper choice. */
        property var pendingWallpaperChoice: null
        /** The image for the pending wallpaper choice. */
        property Item pendingWallpaperImage: null
        /** The wallpaper chosen for the current theme change. */
        property string chosenWallpaperPath: ""

        /** Releases an image only after its opacity reaches zero. */
        function freeHiddenImage(image) {
            if (image.opacity !== 0 || image === layer.screenImage
                    || image === layer.pendingWallpaperImage || effect.visible) return;
            image.source = "";
        }

        /** Stops the prior load and makes the last visible frame stable. */
        function settleCurrentWallpaper() {
            layer.requestNumber++;
            if (layer.pendingWallpaperChoice) {
                layer.pendingWallpaperImage.statusChanged.disconnect(layer.pendingWallpaperChoice);
                layer.pendingWallpaperChoice = null;
                layer.pendingWallpaperImage = null;
            }
            if (progressAnim.running) progressAnim.stop();
            if (effect.visible) layer.finishTransition();

            var current = layer.screenImage;
            var hidden = layer.hiddenImage;
            layer.showWallpaperAtOnce(current, hidden, layer.currentPath ? 1 : 0);
            hidden.source = "";
        }

        /** Sets both image opacities without a fade. */
        function showWallpaperAtOnce(imageToShow, imageToHide, opacity) {
            behaviorA.enabled = false;
            behaviorB.enabled = false;
            imageToShow.opacity = opacity;
            imageToHide.opacity = 0;
            behaviorA.enabled = true;
            behaviorB.enabled = true;
        }

        /** Loads a choice and calls ready only for its newest successful load. */
        function loadChoice(image, path, request, ready) {
            if (!path) {
                image.source = "";
                ready();
                return;
            }

            layer.pendingWallpaperImage = image;
            image.source = "file://" + path;
            if (image.status === Image.Ready) {
                layer.pendingWallpaperImage = null;
                ready();
            } else if (image.status === Image.Error) {
                layer.pendingWallpaperImage = null;
                image.source = "";
            } else {
                var handler = function() {
                    if (image.status === Image.Loading || image.status === Image.Null) return;
                    image.statusChanged.disconnect(handler);
                    if (layer.pendingWallpaperChoice === handler) {
                        layer.pendingWallpaperChoice = null;
                        layer.pendingWallpaperImage = null;
                    }
                    if (request !== layer.requestNumber) return;
                    if (image.status === Image.Ready) ready();
                    else image.source = "";
                };
                layer.pendingWallpaperChoice = handler;
                image.statusChanged.connect(handler);
            }
        }

        /**
         * Loads path into the hidden Image, then cross-fades after Ready.
         * An empty path fades to the solid color underneath.
         */
        function show(path) {
            layer.settleCurrentWallpaper();
            if (path === layer.currentPath) return;

            var request = layer.requestNumber;
            var incoming = layer.hiddenImage;
            var outgoing = layer.screenImage;

            function reveal() {
                incoming.opacity = path ? 1 : 0;
                outgoing.opacity = 0;
                layer.aVisible = !layer.aVisible;
                layer.currentPath = path;
                layer.freeHiddenImage(outgoing);
            }

            layer.loadChoice(incoming, path, request, reveal);
        }

        // --- Theme-switch transition shader (28a) ---

        // The shader reads a mode by its place in Theme.transitionModeIds.
        Connections {
            target: Theme
            function onWallpaperTransition(mode, durationMs) {
                layer.startTransition(mode, durationMs);
            }
        }

        /**
         * Runs one shader transition from the currently-shown frame to
         * Wallpapers.wallpaperFor(modelData.name) for the just-applied
         * theme (Theme.currentKey has already moved to it by the time this
         * signal fires). Loads the new image into the standby Image item
         * first (waiting for Ready so there is no blank frame), then plays
         * the shader over durationMs, then hands off to the plain image.
         */
        function startTransition(mode, durationMs) {
            layer.settleCurrentWallpaper();
            var request = layer.requestNumber;
            var oldPath = layer.currentPath;
            var newPath = layer.wallpaperPath;
            var incoming = layer.hiddenImage;
            var outgoing = layer.screenImage;

            function begin() {
                layer.chosenWallpaperPath = newPath;
                effect.oldSource = outgoing;
                effect.newSource = incoming;
                effect.oldHasImage = oldPath ? 1 : 0;
                effect.newHasImage = newPath ? 1 : 0;
                effect.oldColor = (Theme.fromRaw && Theme.fromRaw.darker_background) || Theme.shell;
                effect.newColor = (Theme.toRaw && Theme.toRaw.darker_background) || Theme.shell;
                effect.modeIndex = Math.max(0, Theme.transitionModeIds.indexOf(mode));
                effect.seed = Math.random() * 1000;
                effect.resolutionPx = Qt.vector2d(layer.width * modelData.devicePixelRatio, layer.height * modelData.devicePixelRatio);
                var toRaw = Theme.toRaw || {};
                for (var i = 0; i < Colors.transitionKeys.length; i++)
                    effect["paletteColor" + i] = toRaw[Colors.transitionKeys[i]] || Theme.shell;
                effect.progress = 0;
                effect.visible = true;
                progressAnim.duration = durationMs;
                progressAnim.restart();
            }

            layer.loadChoice(incoming, newPath, request, begin);
        }

        /** Hides the shader and commits the new frame as the plain visible image (or solid color), with no extra fade. */
        function finishTransition() {
            if (!effect.visible) return;
            var incoming = layer.hiddenImage;
            var outgoing = layer.screenImage;
            layer.showWallpaperAtOnce(incoming, outgoing, layer.chosenWallpaperPath ? 1 : 0);
            layer.aVisible = !layer.aVisible;
            layer.currentPath = layer.chosenWallpaperPath;
            effect.visible = false;
            effect.oldSource = null;
            effect.newSource = null;
            outgoing.source = "";
        }

        NumberAnimation {
            id: progressAnim
            target: effect
            property: "progress"
            from: 0
            to: 1
            onFinished: layer.finishTransition()
        }

        ShaderEffect {
            id: effect
            anchors.fill: parent
            visible: false
            z: 10

            property real progress: 0
            property int modeIndex: 0
            property real seed: 0
            property vector2d resolutionPx: Qt.vector2d(1, 1)
            property color oldColor: "black"
            property color newColor: "black"
            property int oldHasImage: 0
            property int newHasImage: 0
            property color paletteColor0: "black"
            property color paletteColor1: "black"
            property color paletteColor2: "black"
            property color paletteColor3: "black"
            property color paletteColor4: "black"
            property color paletteColor5: "black"
            property var oldSource: null
            property var newSource: null

            fragmentShader: Qt.resolvedUrl("../shaders/transition.frag.qsb")
        }
    }
}
