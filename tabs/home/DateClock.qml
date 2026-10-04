import QtQuick
import qs.common
import qs.services

/**
 * Date and clock cell: live date line and big 12h time, laid out as in the
 * mock's 5C dateClock cell (Berri Dashboard v2.dc.html, ~line 333).
 * It reads the shared minute Clock, so it runs no timer of its own and
 * shows the current time as soon as it becomes visible.
 */
Item {
    id: root

    readonly property date displayTime: Clock.minute

    WhileVisible { service: Clock }

    readonly property string dateText: Qt.formatDateTime(displayTime, "ddd d MMM").toUpperCase()
    readonly property string hourText: {
        var h = displayTime.getHours() % 12;
        return String(h === 0 ? 12 : h);
    }
    readonly property string minuteText: Qt.formatDateTime(displayTime, "mm")
    readonly property string periodText: displayTime.getHours() >= 12 ? "PM" : "AM"

    Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        // Date line: fixed-height box so the glyph sits at the box top
        // instead of leaving the font's ascent leading as dead space above it.
        Item {
            id: dateRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 10

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.dateText
                font.family: Theme.mono
                font.weight: Font.Medium
                font.pixelSize: 10
                font.letterSpacing: 1.4
                color: Theme.dim
            }
        }

        // Time row: fixed-height box matching the mock's line-height-.8 68px
        // time, so the glyph baseline sits near the box bottom.
        Item {
            id: timeRow
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 54

            Text {
                textFormat: Text.PlainText
                id: timeText
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -18
                text: root.hourText + ":" + root.minuteText
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 68
                font.letterSpacing: -2.04
                color: Theme.fg
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: timeText.right
                anchors.leftMargin: 6
                anchors.baseline: timeText.baseline
                text: root.periodText
                font.family: Theme.mono
                font.weight: Font.Medium
                font.pixelSize: 12
                color: Theme.dim
            }
        }
    }
}
