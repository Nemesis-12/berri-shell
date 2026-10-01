import QtQuick
import Quickshell.Widgets
import qs.common

/**
 * One tray app button (20x20, icon 13px), as in the mock's tray option B.
 * The app's own icon always shows in full color.
 * Left click emits activated(); right click emits menuRequested().
 */
Item {
    id: root

    /** The SystemTrayItem this button stands for. */
    required property var trayItem

    /** True while this app's menu is open (keeps the hover fill). */
    property bool menuOpen: false

    /** True for a moment after a left click (accent tint, as in the mock). */
    property bool flash: false

    signal activated()
    signal menuRequested()

    readonly property bool lit: hover.hovered || root.menuOpen

    implicitWidth: 20
    implicitHeight: 20

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: root.lit || root.flash ? PillTrayStyle.hoverFill : PillTrayStyle.hoverFillClear
        ColorFade on color {}
    }

    IconImage {
        id: glyph
        anchors.centerIn: parent
        implicitSize: 13
        source: root.trayItem.icon
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) root.menuRequested();
            else root.activated();
        }
    }
}
