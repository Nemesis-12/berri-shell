import QtQuick
import qs.common
import qs.services

/**
 * Weather cell: condition icon, temperature and condition label, from the
 * Weather singleton (same source and refresh as the pill's mini weather).
 * Mirrors the mock's 5C weather cell (Berri Dashboard v2.dc.html, ~line 337).
 */
Item {
    id: root

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
            color: Theme.accentLight
        }

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.temperatureC + "°" : "--°"
            font.family: Theme.condensed
            font.weight: Font.Medium
            font.pixelSize: 30
            lineHeight: 1
            color: Theme.fg
        }

        MonoText {
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.conditionLabel.toUpperCase() : ""
            font.pixelSize: 10
            font.letterSpacing: 1.2
        }
    }
}
