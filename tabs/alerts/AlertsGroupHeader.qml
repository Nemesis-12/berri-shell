import QtQuick
import qs.common
import qs.services

/** App header above a group of alerts: icon, name, count and a CLEAR button for the group. */
Item {
    id: root

    property string appName: ""
    property string appIcon: ""
    property string countText: ""

    signal clear

    height: 30

    Rectangle {
        anchors.fill: parent
        color: Theme.sunk
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    AlertsAppIcon {
        x: 14
        y: 8
        size: 13
        appName: root.appName
        appIcon: root.appIcon
    }

    Text {
        id: name
        x: 14 + 13 + 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.appName.toUpperCase()
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 1.26
        color: Theme.fg
    }

    AlertsSwap {
        x: name.x + name.implicitWidth + 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.countText
        color: Theme.dim
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
        travel: 5
    }

    HoverButton {
        x: root.width - 6 - width
        anchors.verticalCenter: parent.verticalCenter
        sidePadding: 8
        height: 22
        label: "CLEAR"
        textColor: Theme.dim
        letterSpacing: 0.9
        onClicked: root.clear()
    }
}
