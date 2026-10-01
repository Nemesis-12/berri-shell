import QtQuick
import qs.common
import qs.services

/**
 * Weather tab body (mock 5C SPINE, Berri Weather v2.dc.html): the current
 * conditions card, four readout cells and the next-hours strip on the left
 * (480px wide), and the 7-day column on the right. 1px gaps show the
 * Theme.border backdrop. Clicking a day loads that day into the card, the
 * readouts and the strip with a crossfade; TODAY returns to now.
 */
Item {
    id: root

    /** 24-hour times when true, else "3:05 PM". A settings page can change it. */
    property bool clock24: false

    /** Shows pressure in the fourth readout cell in place of the UV index. */
    property bool showPressure: false

    /** Day picked: 0 is today (now), 1..6 later days. */
    property int selectedDay: 0

    readonly property int gap: 1
    readonly property int leftWidth: 480
    readonly property int topHeight: 272
    readonly property int cardWidth: 300

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // Current conditions card.
    Rectangle {
        x: 0
        y: 0
        width: root.cardWidth
        height: root.topHeight
        color: Theme.card

        WeatherFade {
            anchors.fill: parent
            day: root.selectedDay
            content: Component { WeatherCard { clock24: root.clock24 } }
        }
    }

    // Readout cells.
    Item {
        x: root.cardWidth + root.gap
        y: 0
        width: root.leftWidth - x
        height: root.topHeight

        Rectangle {
            anchors.fill: parent
            color: Theme.card
        }

        WeatherFade {
            anchors.fill: parent
            day: root.selectedDay
            content: Component { WeatherReadouts { showPressure: root.showPressure } }
        }
    }

    // Next-hours strip.
    WeatherFade {
        x: 0
        y: root.topHeight + root.gap
        width: root.leftWidth
        height: root.height - y
        day: root.selectedDay
        content: Component { WeatherHours { clock24: root.clock24 } }
    }

    // 7-day column.
    Item {
        id: dayColumn
        x: root.leftWidth + root.gap
        width: root.width - x
        height: root.height

        readonly property real rowHeight: (height - 30 - 7) / 7

        Rectangle {
            width: parent.width
            height: 30
            color: Theme.sunk

            MonoText {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "7-DAY"
                color: Theme.accentLight
                font.letterSpacing: 1.26
            }
        }

        Repeater {
            model: Weather.days

            WeatherDayRow {
                required property var modelData
                required property int index

                y: 30 + 1 + index * (dayColumn.rowHeight + 1)
                width: dayColumn.width
                height: dayColumn.rowHeight
                day: modelData
                today: index === 0
                selected: index === root.selectedDay
                onClicked: root.selectedDay = index
            }
        }
    }
}
