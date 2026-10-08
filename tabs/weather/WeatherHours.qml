import QtQuick
import "../../logic/WeatherFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Next-hours strip for one day (mock 5C, bottom left): a narrow side label
 * and six hour columns. For today the first column is "Now" and is marked
 * with an accent bar on top.
 */
Item {
    id: root

    /** Day index: 0 is now. */
    property int day: 0
    property bool clock24: false

    /** Number of hour columns. */
    readonly property int columns: 6

    readonly property var hours: (Weather.stripHours(root.day) || []).slice(0, root.columns)
    readonly property bool isNow: root.day === 0

    Rectangle {
        id: side
        width: 24
        height: parent.height
        color: Theme.card

        SideLabel {
            tone: Theme.accentLight
            renderType: Text.CurveRendering
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: root.isNow ? "NEXT " + root.columns + " H" : "HOURLY"
        }
    }

    Repeater {
        model: root.hours

        Rectangle {
            id: cell

            required property var modelData
            required property int index

            readonly property bool marked: root.isNow && index === 0
            readonly property real cellWidth: (root.width - side.width - 1 - (root.columns - 1)) / root.columns

            x: side.width + 1 + index * (cellWidth + 1)
            width: cellWidth
            height: root.height
            color: marked ? Theme.selectionSoft : Theme.card

            Rectangle {
                visible: cell.marked
                width: parent.width
                height: 2
                color: Theme.accentLight
            }

            // Column with space-between: label 9, icon 20, temperature 27.2, chance 9 (14 padding).
            readonly property real spread: (height - 28 - 65.2) / 3

            MonoText {
                x: 14
                y: 14
                text: cell.marked ? "NOW" : Fmt.hourLabel(cell.modelData.time, root.clock24)
                color: cell.marked ? Theme.accentLight : Theme.dim
                font.letterSpacing: 0.54
            }
            Icon {
                x: 14
                y: 14 + 9 + cell.spread
                name: Weather.iconForGroup(Weather.weatherGroup(cell.modelData.code), cell.modelData.isDay)
                size: 20
                strokeWidth: 1.6
                color: Theme.dim
            }
            CondensedText {
                x: 14
                y: 14 + 9 + 20 + 2 * cell.spread + 13.6 - height / 2
                text: Math.round(cell.modelData.tempC) + "°"
                font.pixelSize: 32
                font.letterSpacing: -0.64
            }
            MonoText {
                x: 14
                y: cell.height - 14 - 9
                text: cell.modelData.precipProbability >= 30 ? cell.modelData.precipProbability + "% RAIN" : ""
            }
        }
    }
}
