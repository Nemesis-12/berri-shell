import QtQuick
import "../../logic/WeatherFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Chip that shows the age of the weather data while the last refresh failed
 * (`Weather.error` is set): a clock icon and "2 H AGO", or "NO DATA" before
 * the first good reading. It is hidden while the data is current. The age
 * follows the shared minute clock, which runs only while the chip is visible.
 * Mock 84-weather-error option C: 16 px high, raised, 9 px mono text.
 */
Rectangle {
    id: root

    visible: Weather.error !== ""
    implicitHeight: 16
    implicitWidth: label.x + label.implicitWidth + 6
    color: Theme.raised

    WhileVisible { service: Clock }

    Icon {
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        name: "clock"
        size: 10
        strokeWidth: 2
        color: Theme.fg2
    }

    MonoText {
        id: label
        x: 6 + 10 + 5
        anchors.verticalCenter: parent.verticalCenter
        text: Fmt.staleChip(Weather.updatedAt, Clock.minute.getTime())
        color: Theme.fg2
        font.letterSpacing: 0.9
    }
}
