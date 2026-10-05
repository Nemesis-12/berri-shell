import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import Quickshell
import "../logic/PixelGrid.js" as PixelGrid
import qs.common
import qs.services

/**
 * The Wallpapers tab body (ticket 28): a horizontal carousel of the shared
 * wallpaper library as cards, sliding so the focused card stays centered,
 * plus a trailing "Add wallpaper" card. Mirrors the mock's Wallpapers tab
 * body (Berri Desktop v2.dc.html: wcards markup ~103-116, wOff ~419).
 *
 * Hosted by ThemeNotch.qml's picker body, the same way ThemesCarousel is
 * hosted in the Themes body. ThemeNotch owns keyboard input (Left/Right/
 * Enter/1..9/A/I/Tab, gated to while the picker is open on the walls tab)
 * and calls focusToCurrent()/moveFocus()/applyFocused()/
 * assignFocusedToMonitor()/assignFocusedToAll() here; the SHOW ON row
 * itself is built in ThemeNotch.qml, next to this carousel, since it reads
 * Wallpapers.monitors directly.
 */
Item {
    id: root

    /** Set by ThemeNotch.qml; the monitor the picker opened on, used by focusToCurrent(). */
    property string screenName: ""

    readonly property int cardWidth: 300
    readonly property int cardImageHeight: 170
    readonly property int cardGap: 14
    readonly property int cardStep: cardWidth + cardGap
    // Same viewport width as ThemesCarousel: the picker body's 900px frame
    // minus its 18px*2 side padding.
    readonly property int viewportWidth: 864

    // Card content layout: image, then a small gap, then the label row (ON 1/ON 2/ON 1 · 2).
    // Text heights are fixed to their own pixel size (this codebase's
    // convention, see Profile.qml's name/uptime rows), so this carousel's
    // total content height is exact, not a font-metrics guess.
    readonly property int imageLabelGap: 9
    readonly property int labelRowHeight: 12
    /** Total height of one card's visual content (image + gap + label row); this Item's own height. */
    readonly property int cardContentHeight: cardImageHeight + imageLabelGap + labelRowHeight

    readonly property int frameRadius: 8
    readonly property int removeButtonSize: 26

    /** Index into (library + 1) that is currently focused; the last index is the Add card. */
    property int focusIndex: 0

    readonly property var library: Wallpapers.library
    readonly property bool focusIsAdd: root.focusIndex >= root.library.length
    readonly property string focusedPath: root.focusIsAdd ? "" : (root.library[root.focusIndex] || "")

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    /** Sets focus to the wallpaper shown on screenName, else index 0 (also covers the empty-library case: index 0 is then the Add card). */
    function focusToCurrent() {
        var lib = root.library;
        var target = Wallpapers.wallpaperFor(root.screenName);
        for (var i = 0; i < lib.length; i++) {
            if (lib[i] === target) { root.focusIndex = i; return; }
        }
        root.focusIndex = 0;
    }

    /** Moves focus by `delta` cards, clamped to the library plus the Add card. */
    function moveFocus(delta) {
        var n = root.library.length + 1;
        root.focusIndex = Math.max(0, Math.min(n - 1, root.focusIndex + delta));
    }

    /** Enter key: assigns the focused wallpaper to every monitor, or starts Add on the Add card. */
    function applyFocused() {
        if (root.focusIsAdd) { root.openAdd(); return; }
        root.assignFocusedToAll();
    }

    /**
     * Monitor button / key `1`..`9`: puts the focused wallpaper on that
     * monitor only; if it is already there, removes it (solid color).
     * Other monitors keep their own wallpaper. No-op on the Add card.
     */
    function assignFocusedToMonitor(number) {
        if (root.focusIsAdd) return;
        var monitors = Wallpapers.monitors;
        for (var i = 0; i < monitors.length; i++) {
            if (monitors[i].number !== number) continue;
            if (Wallpapers.numbersShowing(root.focusedPath).indexOf(number) !== -1)
                Wallpapers.unassign(root.focusedPath, [monitors[i].name]);
            else
                Wallpapers.assign(root.focusedPath, [monitors[i].name]);
            return;
        }
    }

    /** `All` button / key `A`: puts the focused wallpaper on every monitor. Does nothing if all already show it, or on the Add card. */
    function assignFocusedToAll() {
        if (root.focusIsAdd) return;
        var monitors = Wallpapers.monitors;
        if (Wallpapers.numbersShowing(root.focusedPath).length === monitors.length) return;
        var names = [];
        for (var i = 0; i < monitors.length; i++) names.push(monitors[i].name);
        Wallpapers.assign(root.focusedPath, names);
    }

    /** Asks the host to close the picker first; the dialog would open under the picker's Overlay window. */
    signal addRequested()
    /** Emitted when the add flow ends: the new wallpaper's path, or "" if none was added. The host reopens the picker. */
    signal addDone(string path)

    /** Asks the host to close the picker; the host then calls chooseFile(). Focus stays where it is. */
    function openAdd() {
        root.addRequested();
    }

    /** Opens the file dialog (called by the host once the picker is fully closed). */
    function chooseFile() {
        root.addWaiting = false;
        picker.open();
    }

    /** True from a picked file until Wallpapers reports the copy. */
    property bool addWaiting: false

    ImagePicker {
        id: picker
        dialogTitle: "Choose Wallpaper"
        nameFilters: ["Images (*.png *.jpg *.jpeg)"]
        startDir: (Quickshell.env("HOME") || "") + "/Pictures"
        fallbackDir: Quickshell.env("HOME") || ""
        onChosen: (path) => {
            root.addWaiting = true;
            Wallpapers.add(path);
        }
        onFinished: if (!root.addWaiting) root.addDone("")
    }

    Connections {
        target: Wallpapers
        function onAddFinished(path) {
            if (!root.addWaiting) return;
            root.addWaiting = false;
            root.addDone(path);
        }
    }

    /** Focuses the card for path, if it is in the library. */
    function focusPath(path) {
        var i = root.library.indexOf(path);
        if (i !== -1) root.focusIndex = i;
    }

    /** Rounded-rect outline path (clockwise, top-left start), for the Add card's dashed frame. */
    function roundedRectPath(w, h, r) {
        return "M" + r + " 0" +
            "H" + (w - r) +
            "A" + r + " " + r + " 0 0 1 " + w + " " + r +
            "V" + (h - r) +
            "A" + r + " " + r + " 0 0 1 " + (w - r) + " " + h +
            "H" + r +
            "A" + r + " " + r + " 0 0 1 0 " + (h - r) +
            "V" + r +
            "A" + r + " " + r + " 0 0 1 " + r + " 0" +
            "Z";
    }

    clip: true

    Item {
        id: track
        width: row.width
        height: root.cardContentHeight
        anchors.verticalCenter: parent.verticalCenter
        // Centers the focused card: -(focusIndex * step - (viewport - card) / 2).
        x: PixelGrid.snap(-(root.focusIndex * root.cardStep - (root.viewportWidth - root.cardWidth) / 2), root.dpr)
        Behavior on x {
            SpringMotion {
                duration: 500
            }
        }

        Row {
            id: row
            spacing: root.cardGap

            Repeater {
                model: root.visible ? root.library : []

                delegate: Item {
                    id: card
                    required property string modelData
                    required property int index

                    readonly property bool focused: index === root.focusIndex
                    readonly property var numbersShowing: Wallpapers.numbersShowing(card.modelData)
                    readonly property string onLabel: card.numbersShowing.length === 0 ? ""
                        : card.numbersShowing.length > 1 ? "ON " + card.numbersShowing.join(" · ")
                        : "ON " + card.numbersShowing[0]

                    width: root.cardWidth
                    height: root.cardContentHeight
                    scale: focused ? 1 : 0.93
                    opacity: focused ? 1 : 0.7

                    Behavior on scale {
                        SpringMotion {
                            duration: 450
                        }
                    }
                    Fade on opacity { duration: Theme.stateMs }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusIndex = card.index
                    }

                    Rectangle {
                        id: imageFrame
                        width: root.cardWidth
                        height: root.cardImageHeight
                        radius: root.frameRadius
                        clip: true
                        color: Theme.card

                        Image {
                            anchors.fill: parent
                            source: card.modelData.length > 0 ? ("file://" + card.modelData) : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(width * root.dpr, height * root.dpr)
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            cache: false
                        }
                    }

                    Rectangle {
                        anchors.fill: imageFrame
                        radius: root.frameRadius
                        color: "transparent"
                        border.width: 2
                        border.color: card.focused ? Theme.accent : Theme.border
                        ColorFade on border.color { duration: Theme.stateMs }
                    }

                    // Remove button, top-right over the image (shown even for the only wallpaper).
                    HoverButton {
                        id: removeBtn
                        anchors.top: imageFrame.top
                        anchors.right: imageFrame.right
                        anchors.topMargin: 8
                        anchors.rightMargin: 8
                        width: root.removeButtonSize
                        height: root.removeButtonSize
                        radius: 5
                        fill: hovered ? Qt.rgba(0, 0, 0, 0.8) : Qt.rgba(0, 0, 0, 0.55)
                        hoverFill: "transparent"
                        icon: "x"
                        iconSize: 12
                        iconStrokeWidth: 2.4
                        textColor: "white"
                        hoverTextColor: "white"
                        ColorFade on color {}

                        onClicked: {
                            var removedIndex = card.index;
                            var focusBefore = root.focusIndex;
                            Wallpapers.remove(card.modelData);
                            // Keep focus on the same card, or its nearest remaining neighbor.
                            if (removedIndex < focusBefore) root.focusIndex = focusBefore - 1;
                            else root.focusIndex = Math.max(0, Math.min(focusBefore, root.library.length - 1));
                        }
                    }

                    Row {
                        anchors.top: imageFrame.bottom
                        anchors.topMargin: root.imageLabelGap
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        spacing: 8

                        Text {
                            textFormat: Text.PlainText
                            visible: card.onLabel.length > 0
                            text: card.onLabel
                            font.family: Theme.mono
                            font.weight: Font.DemiBold
                            font.pixelSize: 9
                            font.letterSpacing: 0.72
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 9
                            height: 9
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.accentLight
                        }
                    }
                }
            }

            // Trailing "Add wallpaper" card: dashed 2px frame (Shape, since a
            // dashed Rectangle border does not exist in QML), a plus icon and
            // the shared-library hint text.
            Item {
                id: addCard
                readonly property bool focused: root.focusIsAdd

                width: root.cardWidth
                height: root.cardContentHeight
                scale: focused ? 1 : 0.93
                opacity: focused ? 1 : 0.7

                Behavior on scale {
                    SpringMotion {
                        duration: 450
                    }
                }
                Fade on opacity { duration: Theme.stateMs }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAdd()
                }

                Item {
                    id: addFrame
                    width: root.cardWidth
                    height: root.cardImageHeight

                    Shape {
                        anchors.fill: parent
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: addCard.focused ? Theme.accent : Theme.border
                            strokeWidth: 2
                            fillColor: "transparent"
                            strokeStyle: ShapePath.DashLine
                            dashPattern: [3, 2]
                            capStyle: ShapePath.FlatCap
                            ColorFade on strokeColor { duration: Theme.stateMs }
                            PathSvg { path: root.roundedRectPath(root.cardWidth, root.cardImageHeight, root.frameRadius) }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "plus"
                            size: 26
                            strokeWidth: 2
                            color: Theme.dim
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "PNG or JPG · stays with " + (Theme.current ? Theme.current.name : "this theme")
                            font.family: Theme.mono
                            font.weight: Font.Medium
                            font.pixelSize: 10
                            color: Theme.dim
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.top: addFrame.bottom
                    anchors.topMargin: root.imageLabelGap
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    text: "Add wallpaper"
                    font.family: Theme.condensed
                    font.weight: Font.DemiBold
                    font.pixelSize: 12
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 12
                    height: 12
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.dim
                }
            }
        }
    }
}
