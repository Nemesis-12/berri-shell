import QtQuick
import qs.services
import qs.common

/**
 * One notification in the alerts list: title and time, body, and the three
 * row actions. An unread row has the soft selection fill and a 2px bar on the
 * left; both fade out when it is read. Clicking the row marks it read.
 */
Item {
    id: root

    property string title: ""
    property string body: ""
    property string timeText: ""
    property bool read: false

    signal opened
    signal markRead
    signal snooze
    signal dismiss

    readonly property real textWidth: width - 14 - 12 - 6 - actions.width

    height: 11 + column.implicitHeight + 12 + 1

    Rectangle {
        anchors.fill: parent
        color: Theme.card
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.selectionSoft
        opacity: root.read ? 0 : 1
        Fade on opacity  { duration: Theme.stateMs }
    }

    Rectangle {
        width: 2
        height: parent.height
        color: Theme.accentLight
        opacity: root.read ? 0 : 1
        Fade on opacity  { duration: Theme.stateMs }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.opened()
    }

    Column {
        id: column
        x: 14
        y: 11
        width: root.textWidth
        spacing: 6

        Item {
            width: parent.width
            height: titleText.lineCount * 17.25

            Text {
                textFormat: Text.PlainText
                id: titleText
                y: -1.5
                width: parent.width - stamp.implicitWidth - 10
                text: root.title
                wrapMode: Text.Wrap
                font.family: Theme.condensed
                font.pixelSize: 15
                font.weight: Font.Medium
                lineHeight: 17.25
                lineHeightMode: Text.FixedHeight
                color: root.read ? Theme.fg2 : Theme.fg
                ColorFade on color  { duration: Theme.stateMs }
            }

            Text {
                textFormat: Text.PlainText
                id: stamp
                anchors.right: parent.right
                y: 6
                text: root.timeText
                font.family: Theme.mono
                font.pixelSize: 9
                font.weight: Font.Medium
                color: Theme.dim
            }
        }

        Item {
            width: parent.width
            height: bodyText.lineCount * 18.2
            visible: root.body !== ""

        Text {
            textFormat: Text.PlainText
            id: bodyText
            y: 0.5
            width: parent.width
            text: root.body
            wrapMode: Text.Wrap
            font.family: Theme.condensed
            font.pixelSize: 13
            lineHeight: 18.2
            lineHeightMode: Text.FixedHeight
            color: Theme.dim
        }
        }
    }

    Row {
        id: actions
        x: root.width - 6 - width
        y: 11
        spacing: 1

        AlertsActionButton { icon: "check"; shown: !root.read; onClicked: root.markRead() }
        AlertsActionButton { icon: "clock"; onClicked: root.snooze() }
        AlertsActionButton { icon: "x"; onClicked: root.dismiss() }
    }
}
