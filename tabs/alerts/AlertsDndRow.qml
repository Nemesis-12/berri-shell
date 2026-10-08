import QtQuick
import qs.common
import qs.notifications
import qs.services

/**
 * Do not disturb row of the alerts filter column: moon icon, label and a
 * switch. A click toggles do not disturb in the Notifications store. The tab
 * sets `y` and `width`.
 */
Item {
    id: root

    height: 56

    readonly property bool on: Notifications.dnd

    Rectangle {
        anchors.fill: parent
        color: Theme.card
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.hover
        opacity: dndArea.containsMouse && !root.on ? 1 : 0
        Fade on opacity {}
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.selectionSoft
        opacity: root.on ? 1 : 0
        Fade on opacity  { duration: Theme.stateMs }
    }

    Rectangle {
        width: parent.width
        height: 2
        color: Theme.accentLight
        opacity: root.on ? 1 : 0
        Fade on opacity  { duration: Theme.stateMs }
    }

    Icon {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        name: "moon"
        size: 17
        strokeWidth: 1.6
        color: root.on ? Theme.accentLight : Theme.dim
        ColorFade on color  { duration: Theme.stateMs }
    }

    Text {
        textFormat: Text.PlainText
        x: 14 + 17 + 10
        anchors.verticalCenter: parent.verticalCenter
        text: "DO NOT DISTURB"
        font.family: Theme.mono
        font.pixelSize: 10
        font.weight: Font.Medium
        font.letterSpacing: 1.2
        color: Theme.fg
    }

    ToggleSwitch {
        x: parent.width - 14 - width
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 16
        radius: 0
        knobSize: 10
        knobRadius: 0
        checked: root.on
        interactive: false
        onColor: Theme.accentLight
        emphasized: true
        slideMs: 200
    }

    MouseArea {
        id: dndArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifications.setDnd(!Notifications.dnd)
    }
}
