import QtQuick
import "../../logic/Times.js" as Times
import qs.common
import qs.services

/** One calendar source with its color, age and actions. */
Item {
    id: row

    required property real nameWidth
    required property real updatedX
    required property real now
    required property color redColor

    signal colorRequested(Item square)

    required property string calId
    required property string name
    required property string kind
    required property string calColor
    required property bool hidden
    required property int itemCount
    required property string source
    required property real updatedAt
    required property string failure

    readonly property color tint: CalendarColors.resolve(calColor)
    readonly property bool isLink: kind === "link"
    readonly property string sourceLine: failure !== ""
        ? failure
        : isLink ? (source + " · " + Times.ageText(updatedAt, row.now, "ago")) : (itemCount + (itemCount === 1 ? " item" : " items"))

    width: ListView.view.width
    height: 46

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    // Color square: click opens the color popover of this calendar.
    Rectangle {
        id: square
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -0.5
        width: 12
        height: 12
        color: row.hidden ? "transparent" : row.tint
        border.width: 1.5
        border.color: row.tint

        ColorFade on color { duration: Theme.stateMs }

        // Hover: a light veil, like the picker squares.
        Rectangle {
            anchors.fill: parent
            color: "white"
            opacity: squareMouse.containsMouse ? 0.14 : 0

            Fade on opacity {}
        }

        MouseArea {
            id: squareMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.colorRequested(square)
        }
    }

    // Name and source line, 5px apart, in boxes as tall as their CSS lines.
    Column {
        x: 12 + 12 + 10
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -0.5
        width: row.nameWidth - 22
        spacing: 5

        Item {
            width: parent.width
            height: 15.4

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: row.name
                elide: Text.ElideRight
                font.family: Theme.condensed
                font.pixelSize: 14
                font.weight: Font.Medium
                color: row.hidden ? Theme.mute : Theme.fg

                ColorFade on color { duration: Theme.stateMs }
            }
        }

        Item {
            width: parent.width
            height: 9

            MonoText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: row.sourceLine.toUpperCase()
                elide: Text.ElideRight
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 0.36
                color: row.failure !== "" ? row.redColor : Theme.dim
                ColorFade on color { duration: Theme.stateMs }
            }
        }
    }

    MonoText {
        x: row.updatedX
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -0.5
        text: row.kind === "local" ? "—" : Times.ageText(row.updatedAt, row.now, "ago").toUpperCase()
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 0.36
        color: Theme.dim
    }

    // Refresh (links) and remove (files and links).
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -0.5

        HoverButton {
            width: 24
            height: 24
            icon: row.hidden ? "eye-off" : "eye"
            iconSize: 13
            iconStrokeWidth: 1.8
            textColor: Theme.mute
            onClicked: Calendar.setCalendarHidden(row.calId, !row.hidden)
        }

        Rectangle {
            visible: row.isLink
            width: 24
            height: 24
            color: refreshMouse.containsMouse ? Theme.hover : "transparent"

            ColorFade on color {}

            Icon {
                anchors.centerIn: parent
                name: "rotate-cw"
                size: 13
                strokeWidth: 1.8
                color: refreshMouse.containsMouse ? Theme.fg : Theme.mute
                ColorFade on color {}
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Calendar.refresh(row.calId)
            }
        }

        HoverButton {
            visible: row.kind !== "local"
            width: 24
            height: 24
            icon: "x"
            iconSize: 13
            iconStrokeWidth: 1.8
            textColor: Theme.mute
            onClicked: Calendar.removeCalendar(row.calId)
        }
    }
}
