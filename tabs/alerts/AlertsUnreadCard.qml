import QtQuick
import qs.notifications
import qs.services

/**
 * Unread count card at the top of the alerts filter column: a rotated INBOX
 * label, the big count and the UNREAD label. The count slides on change.
 * The tab sets `width`.
 */
Rectangle {
    id: root

    height: 96
    color: Theme.card
    clip: true

    Text {
        textFormat: Text.PlainText
        x: 10
        y: 84
        rotation: -90
        transformOrigin: Item.TopLeft
        text: "INBOX"
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 1.62
        color: Theme.dim
    }

    AlertsSwap {
        id: bigCount
        x: 29
        y: 84 - 48 - 12.5
        height: 48
        text: String(Notifications.unreadCount)
        color: Theme.fg
        font.family: Theme.condensed
        font.pixelSize: 60
        font.weight: Font.Medium
        font.letterSpacing: -1.8
        lineHeight: 48
        travel: 16
    }

    Text {
        textFormat: Text.PlainText
        x: bigCount.x + bigCount.width + 8
        y: 84 - 2 - 9 - 2
        text: "UNREAD"
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 1.26
        color: Theme.dim
    }
}
