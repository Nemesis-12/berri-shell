import QtQuick
import qs.services

/**
 * Header shared by the toggle-grid device lists (Wi-Fi, Bluetooth): a back
 * button on the left, a mono title, and an on/off switch on the right.
 */
Item {
    id: root

    property string title: ""
    property bool checked: false

    signal backClicked
    signal toggled

    height: 28

    Rectangle {
        id: backButton
        width: 24
        height: 24
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        radius: 3
        border.width: 1
        border.color: backMouse.containsMouse ? Theme.accentLine : Theme.border
        color: Theme.shell

        ColorFade on border.color {}

        Icon {
            anchors.centerIn: parent
            name: "chevron-left"
            size: 12
            strokeWidth: 2
            color: backMouse.containsMouse ? Theme.accentLight : Theme.fg2

            ColorFade on color {}
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.backClicked()
        }
    }

    MonoText {
        anchors.left: backButton.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        font.pixelSize: 10
        font.letterSpacing: 0.14 * 10
        color: Theme.fg2
    }

    ToggleSwitch {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        onToggled: root.toggled()
    }
}
