import QtQuick
import qs.common
import qs.notifications
import qs.services

/**
 * Do not disturb banner above the alert list, with a TURN OFF button. One
 * progress value drives height and fade; the list below follows the height,
 * so closing plays opening backwards. The tab sets `y`, `width` and `gap`
 * (the 1px space between stacked parts).
 */
Item {
    id: root

    property int gap: 1

    height: (bannerBody.height + root.gap) * shownAmount
    clip: true
    visible: shownAmount > 0.001

    property real shownAmount: Notifications.dnd ? 1 : 0
    Behavior on shownAmount {
        StandardMotion {
            duration: 260
        }
    }

    Rectangle {
        id: bannerBody
        width: parent.width
        height: 46
        color: Theme.selectionSoft
        opacity: root.shownAmount

        Rectangle {
            width: parent.width
            height: 2
            color: Theme.accentLight
        }

        Text {
            textFormat: Text.PlainText
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 14 - 6 - turnOff.width - 10
            elide: Text.ElideRight
            text: "DO NOT DISTURB IS ON · NEW NOTIFICATIONS ARRIVE SILENTLY"
            font.family: Theme.mono
            font.pixelSize: 9
            font.weight: Font.Medium
            font.letterSpacing: 0.54
            color: Theme.fg2
        }

        HoverButton {
            id: turnOff
            x: parent.width - 6 - width
            anchors.verticalCenter: parent.verticalCenter
            sidePadding: 10
            height: 26
            fill: Theme.accentLight
            hoverFill: Qt.rgba(1, 1, 1, 0.18)
            textColor: Theme.onAccent
            hoverTextColor: Theme.onAccent
            letterSpacing: 1.08
            label: "TURN OFF"
            enabled: Notifications.dnd
            onClicked: Notifications.setDnd(false)
        }
    }
}
