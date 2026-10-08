import QtQuick
import qs.common
import qs.services

/**
 * Banner at the bottom of the calendar tab for a failed save. Set `message`;
 * an empty message hides it. The tab clears `message` on `dismissed`.
 */
Rectangle {
    id: root

    property string message: ""
    signal dismissed

    z: 200
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 36
    color: Theme.raised
    opacity: root.message !== "" ? 1 : 0
    visible: opacity > 0
    enabled: root.message !== ""
    Fade on opacity { duration: Theme.stateMs }

    Rectangle {
        width: 2
        height: parent.height
        color: CalendarColors.paletteColor("red", Theme.accent)
    }

    MonoText {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: dismissError.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.message
        elide: Text.ElideRight
        font.pixelSize: 10
        color: Theme.fg
    }

    HoverButton {
        id: dismissError
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        icon: "x"
        iconSize: 13
        onClicked: root.dismissed()
    }
}
