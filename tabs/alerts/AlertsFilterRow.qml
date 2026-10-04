import QtQuick
import qs.common
import qs.services

/**
 * One row of the filter column: icon, label and count. The selected row has
 * the soft selection fill and a 2px bar on the left. `icon` is a Lucide name
 * (All, Unread); with an empty `icon` the app's own icon is used.
 */
Item {
    id: root

    property string label: ""
    property string icon: ""
    property string appName: ""
    property string appIcon: ""
    property color iconColor: Theme.fg2
    property string countText: ""
    property bool selected: false

    signal clicked

    height: 32

    Rectangle {
        anchors.fill: parent
        color: Theme.card
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.hover
        opacity: area.containsMouse && !root.selected ? 1 : 0
        Fade on opacity {}
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.selectionSoft
        opacity: root.selected ? 1 : 0
        Fade on opacity  { duration: Theme.stateMs }
    }

    Rectangle {
        width: 2
        height: parent.height
        color: Theme.accentLight
        opacity: root.selected ? 1 : 0
        Fade on opacity  { duration: Theme.stateMs }
    }

    Icon {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon !== ""
        name: root.icon
        size: 14
        strokeWidth: 1.6
        color: root.iconColor
    }

    AlertsAppIcon {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon === ""
        size: 14
        appName: root.appName
        appIcon: root.appIcon
        color: root.iconColor
    }

    Text {
        textFormat: Text.PlainText
        x: 14 + 14 + 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.condensed
        font.pixelSize: 13
        font.weight: Font.Medium
        color: root.selected ? Theme.fg : Theme.fg2
        ColorFade on color  { duration: Theme.stateMs }
    }

    AlertsSwap {
        x: root.width - 14 - width
        anchors.verticalCenter: parent.verticalCenter
        text: root.countText
        color: Theme.dim
        font.family: Theme.mono
        font.pixelSize: 10
        font.weight: Font.Medium
        travel: 5
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
