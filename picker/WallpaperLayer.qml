import QtQuick
import Quickshell
import Quickshell.Wayland
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
            Behavior on opacity { id: behaviorA; NumberAnimation { duration: Theme.stateMs; easing.type: Easing.OutCubic } }
            onOpacityChanged: layer.releaseFaded(imageA)
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
            Behavior on opacity { id: behaviorB; NumberAnimation { duration: Theme.stateMs; easing.type: Easing.OutCubic } }
            onOpacityChanged: layer.releaseFaded(imageB)
        }

        /** true when imageA is the currently-visible layer (imageB is the standby one). */
        property bool aVisible: false

        /** Absolute path currently shown (matches whichever Image is visible), or "" for the solid color. Tracked separately from wallpaperPath so a transition still knows its "old frame" after Theme.currentKey has already moved on to the new theme. */
        property string currentPath: ""

        /** The newest load requested for this screen. */
        property int requestNumber: 0
        property var loadHandler: null
        property Item loadingImage: null
        property string transitionPath: ""

        /** Releases an image only after its opacity reaches zero. */
        function releaseFaded(image) {
            if (image.opacity !== 0 || image === (layer.aVisible ? imageA : imageB)
                    || image === layer.loadingImage || effect.visible) return;
            image.source = "";
        }

        /** Stops the prior load and makes the last visible frame stable. */
        function prepareChoice() {
            layer.requestNumber++;
            if (layer.loadHandler) {
                layer.loadingImage.statusChanged.disconnect(layer.loadHandler);
                layer.loadHandler = null;
                layer.loadingImage = null;
            }
            if (progressAnim.running) progressAnim.stop();
            if (effect.visible) layer.finishTransition();

            var current = layer.aVisible ? imageA : imageB;
            var hidden = layer.aVisible ? imageB : imageA;
            behaviorA.enabled = false;
            behaviorB.enabled = false;
            current.opacity = layer.currentPath ? 1 : 0;
            hidden.opacity = 0;
            hidden.source = "";
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

            layer.loadingImage = image;
            image.source = "file://" + path;
            if (image.status === Image.Ready) {
                layer.loadingImage = null;
                ready();
            } else if (image.status === Image.Error) {
                layer.loadingImage = null;
                image.source = "";
            } else {
                var handler = function() {
                    if (image.status === Image.Loading || image.status === Image.Null) return;
                    image.statusChanged.disconnect(handler);
                    if (layer.loadHandler === handler) {
                        layer.loadHandler = null;
                        layer.loadingImage = null;
                    }
                    if (request !== layer.requestNumber) return;
                    if (image.status === Image.Ready) ready();
                    else image.source = "";
                };
                layer.loadHandler = handler;
                image.statusChanged.connect(handler);
            }
        }

        /**
         * Loads path into the hidden Image, then cross-fades after Ready.
         * An empty path fades to the solid color underneath.
         */
        function show(path) {
            layer.prepareChoice();
            if (path === layer.currentPath) return;

            var request = layer.requestNumber;
            var incoming = layer.aVisible ? imageB : imageA;
            var outgoing = layer.aVisible ? imageA : imageB;

            function reveal() {
                incoming.opacity = path ? 1 : 0;
                outgoing.opacity = 0;
                layer.aVisible = !layer.aVisible;
                layer.currentPath = path;
                layer.releaseFaded(outgoing);
            }

            layer.loadChoice(incoming, path, request, reveal);
        }

        // --- Theme-switch transition shader (28a) ---

        readonly property var transitionModeIndex: ({ "A": 0, "B": 1, "C2": 2, "D": 3, "F": 4 })

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
            layer.prepareChoice();
            var request = layer.requestNumber;
            var oldPath = layer.currentPath;
            var newPath = layer.wallpaperPath;
            var incoming = layer.aVisible ? imageB : imageA;
            var outgoing = layer.aVisible ? imageA : imageB;

            function begin() {
                layer.transitionPath = newPath;
                effect.oldSource = outgoing;
                effect.newSource = incoming;
                effect.oldHasImage = oldPath ? 1 : 0;
                effect.newHasImage = newPath ? 1 : 0;
                effect.oldColor = (Theme.fromRaw && Theme.fromRaw.darker_background) || Theme.shell;
                effect.newColor = (Theme.toRaw && Theme.toRaw.darker_background) || Theme.shell;
                effect.modeIndex = layer.transitionModeIndex[mode] !== undefined ? layer.transitionModeIndex[mode] : 0;
                effect.seed = Math.random() * 1000;
                effect.resolutionPx = Qt.vector2d(layer.width * modelData.devicePixelRatio, layer.height * modelData.devicePixelRatio);
                var toRaw = Theme.toRaw || {};
                var order6 = ["darker_background", "dark_background", "background", "lighter_background", "selection", "accent"];
                effect.paletteColor0 = toRaw[order6[0]] || Theme.shell;
                effect.paletteColor1 = toRaw[order6[1]] || Theme.shell;
                effect.paletteColor2 = toRaw[order6[2]] || Theme.shell;
                effect.paletteColor3 = toRaw[order6[3]] || Theme.shell;
                effect.paletteColor4 = toRaw[order6[4]] || Theme.shell;
                effect.paletteColor5 = toRaw[order6[5]] || Theme.shell;
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
            var incoming = layer.aVisible ? imageB : imageA;
            var outgoing = layer.aVisible ? imageA : imageB;
            behaviorA.enabled = false;
            behaviorB.enabled = false;
            incoming.opacity = layer.transitionPath ? 1 : 0;
            outgoing.opacity = 0;
            layer.aVisible = !layer.aVisible;
            layer.currentPath = layer.transitionPath;
            behaviorA.enabled = true;
            behaviorB.enabled = true;
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
