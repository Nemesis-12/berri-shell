import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../../logic/PixelGrid.js" as PixelGrid
import qs.common
import qs.picker
import qs.services

/**
 * Sticker cell (ticket 23): shows a user-picked image, or nothing at rest
 * if no sticker file exists yet. Clicking opens ImagePicker's chooser, the
 * same picker Profile uses; Pill closes the panel first via
 * stickerClicked(), since the panel's own Overlay layer would otherwise sit
 * above a normal dialog window.
 *
 * The chosen file is copied to ~/.config/berri-shell/sticker.<ext>, replacing
 * any older sticker.* so only one exists. .gif and .webp play through
 * AnimatedImage (a still WebP also renders fine there); PNG/JPEG use a small
 * display copy in a plain Image. Only one of the two loads the file. Animation is paused while the panel is closed (panelOpen),
 * so a hidden GIF does not keep repainting.
 */
Item {
    id: root

    readonly property string homePath: Quickshell.env("HOME") || ""
    readonly property string configDirPath: homePath + "/.config/berri-shell"
    readonly property string picturesDirPath: homePath + "/Pictures"

    /** True while the dashboard panel is open; drives AnimatedImage.playing. */
    property bool panelOpen: false

    /** Output scale of the screen this cell is on; used to decode images at native sharpness. */
    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    /** Final size of the cell at rest (set by HomeTab). The cell is smaller while the panel opens; decoding at the final size keeps the decode from restarting on every frame. */
    property size restSize: Qt.size(0, 0)
    readonly property size decodeSize: Qt.size(restSize.width * dpr, restSize.height * dpr)

    /** The saved source stays unchanged. A still image uses a small display copy. */
    property string stickerPath: ""
    property string stickerSource: ""
    readonly property bool useAnimatedImage: {
        var path = root.stickerPath.toLowerCase();
        return path.endsWith(".gif") || path.endsWith(".webp");
    }
    property bool copyAgain: false
    property string copySourcePath: ""
    property int copyWidth: 0
    property int copyHeight: 0

    function fileUrl(path) {
        return "file://" + path + "?" + Date.now();
    }

    function makeDisplayCopy() {
        if (!stickerPath || useAnimatedImage) return;
        var width = Math.round(restSize.width * 2);
        var height = Math.round(restSize.height * 2);
        if (width < 1 || height < 1) return;
        if (displayCopy.running) { copyAgain = true; return; }
        copySourcePath = stickerPath;
        copyWidth = width;
        copyHeight = height;
        displayCopy.command = [
            "sh",
            Quickshell.shellPath("scripts/sticker-display-copy.sh"),
            stickerPath,
            configDirPath + "/sticker-display.png",
            String(width),
            String(height)
        ];
        displayCopy.running = true;
    }

    onRestSizeChanged: makeDisplayCopy()

    Process {
        id: displayCopy
        onExited: (exitCode) => {
            if (root.copyAgain) {
                root.copyAgain = false;
                root.makeDisplayCopy();
                return;
            }
            if (root.copySourcePath !== root.stickerPath) return;
            if (root.copyWidth !== Math.round(root.restSize.width * 2)
                    || root.copyHeight !== Math.round(root.restSize.height * 2)) return;
            root.stickerSource = root.fileUrl(exitCode === 0
                ? root.configDirPath + "/sticker-display.png" : root.stickerPath);
        }
    }

    /** Click on the cell; Pill closes the panel then calls openStickerChooser(). */
    signal stickerClicked()

    function openStickerChooser() {
        picker.open();
    }

    ImagePicker {
        id: picker
        dialogTitle: "Choose Sticker"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif)"]
        startDir: root.picturesDirPath
        fallbackDir: root.homePath
        onChosen: (path) => setSticker.copyFrom(path)
    }

    Process {
        id: setSticker

        // Copy a supported choice before removing older sticker files.
        function copyFrom(path) {
            setSticker.command = ["sh", Quickshell.shellPath("scripts/set-sticker.sh"),
                root.configDirPath, path];
            setSticker.running = true;
        }

        onExited: (exitCode) => {
            if (exitCode !== 0) return;
            root.stickerPath = "";
            root.stickerSource = "";
            root.findSticker();
        }
    }

    function findSticker() {
        if (!findStickerProc.running) findStickerProc.running = true;
    }

    Process {
        id: findStickerProc
        // sh -c: $1 is the config directory.
        command: ["sh", "-c", 'ls "$1"/sticker.* 2>/dev/null | head -n1',
            "sh", root.configDirPath]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var path = text.trim();
                if (path === root.stickerPath) return;
                root.stickerPath = path;
                root.stickerSource = path && root.useAnimatedImage ? root.fileUrl(path) : "";
                root.makeDisplayCopy();
            }
        }
    }

    // Detect a new or removed sticker file, including changes made outside the picker.
    FolderListModel {
        folder: "file://" + root.configDirPath
        nameFilters: ["sticker.png", "sticker.jpg", "sticker.jpeg", "sticker.gif", "sticker.webp"]
        showDirs: false
        onCountChanged: root.findSticker()
    }

    // Watch the source without loading its binary contents into a text buffer.
    FileView {
        path: root.stickerPath
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: {
            if (root.useAnimatedImage) root.stickerSource = root.fileUrl(root.stickerPath);
            else root.makeDisplayCopy();
        }
        onLoadFailed: root.findSticker()
    }

    Component.onCompleted: root.findSticker()

    // Only one image item loads the file: a plain Image for PNG/JPEG, an
    // AnimatedImage for GIF/WebP. Both decode at the fixed `decodeSize`, so
    // the cell resizing while the panel opens never restarts the decode. The
    // The image stays loaded through the close fade, then unloads when the
    // tab is hidden. A large file can finish decoding after the panel has
    // faded in: it fades in then, no pop.
    Loader {
        anchors.fill: parent
        active: root.visible && root.stickerSource.length > 0
        sourceComponent: root.useAnimatedImage ? animatedPicture : stillPicture
    }

    // Still image, crop-filled to the cell.
    Component {
        id: stillPicture

        Image {
            source: root.stickerSource
            fillMode: Image.PreserveAspectCrop
            sourceSize: root.decodeSize
            smooth: true
            mipmap: true
            asynchronous: true
            cache: false
            opacity: status === Image.Ready ? 1 : 0
            Fade on opacity { duration: Theme.stateMs }
        }
    }

    // GIF/WebP: only plays while the panel is open. Fit (not cropped) so the
    // whole animation stays visible, letterboxed by the cell's card color.
    Component {
        id: animatedPicture

        AnimatedImage {
            source: root.stickerSource
            fillMode: Image.PreserveAspectFit
            sourceSize: root.decodeSize
            smooth: true
            mipmap: true
            asynchronous: true
            cache: false
            playing: root.panelOpen
            opacity: status === Image.Ready ? 1 : 0
            Fade on opacity { duration: Theme.stateMs }
        }
    }

    // Hover hint: dark veil + centered "image" icon, shown whether or not a
    // sticker is set, so the user always sees the cell is clickable.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: hoverHandler.hovered ? 0.3 : 0
        Fade on opacity {}
    }

    Icon {
        anchors.centerIn: parent
        name: "image"
        size: 20
        strokeWidth: 1.5
        color: Theme.fg2
        opacity: hoverHandler.hovered ? 1 : 0
        Fade on opacity {}
    }

    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.stickerClicked()
    }
}
