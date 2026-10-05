import QtQuick
import qs.common
import qs.services

/**
 * Weather cell: condition icon, temperature and condition label, from the
 * Weather singleton (same source and refresh as the pill's mini weather).
 * Mirrors the mock's 5C weather cell (Berri Dashboard v2.dc.html, ~line 337).
 * While the last refresh failed (`Weather.error`), icon and temperature turn
 * dim and a StaleChip with the data age replaces the condition label.
 */
Item {
    id: root

    /** True while the last refresh failed: icon and temperature turn dim and a chip replaces the label. */
    readonly property bool stale: Weather.error !== ""

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        spacing: 12

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: Weather.iconName
            size: 22
            strokeWidth: 1.5
            color: root.stale ? Theme.dim : Theme.accentLight
            Behavior on color { StandardColorMotion { duration: Theme.stateMs } }
        }

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.temperatureC + "°" : "--°"
            font.family: Theme.condensed
            font.weight: Font.Medium
            font.pixelSize: 30
            lineHeight: 1
            color: root.stale ? Theme.dim : Theme.fg
            Behavior on color { StandardColorMotion { duration: Theme.stateMs } }
        }

        StaleChip {
            anchors.verticalCenter: parent.verticalCenter
        }

        MonoText {
            visible: !root.stale
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.conditionLabel.toUpperCase() : ""
            font.pixelSize: 10
            font.letterSpacing: 1.2
        }
    }
}
