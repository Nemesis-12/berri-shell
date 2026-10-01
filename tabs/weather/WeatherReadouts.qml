import QtQuick
import "../../logic/WeatherFormat.js" as Fmt
import qs.common
import qs.services

/**
 * The four readout cells of one day (mock 5C, right of the card): humidity,
 * wind, precipitation and UV index (or pressure). One Theme.border backdrop
 * shows through the 1px gaps.
 */
Item {
    id: root

    /** Day index: 0 is now. */
    property int day: 0

    /** Shows pressure in place of the UV index. */
    property bool showPressure: false

    readonly property var detail: { Weather.updatedAt; return Weather.dayDetail(root.day) || ({}); }

    function num(v) {
        return v === undefined || v === null ? "--" : Math.round(v).toString();
    }

    readonly property var cells: [
        { label: "HUMIDITY", icon: "droplet", value: root.num(root.detail.humidity), unit: "%",
          sub: "Dew point " + root.num(root.detail.dewPointC) + "°" },
        { label: "WIND", icon: "wind", value: root.num(root.detail.windKmh), unit: "km/h",
          sub: (root.detail.windDirection === undefined ? "" : Fmt.compass(root.detail.windDirection) + " · ")
               + "gusts " + root.num(root.detail.gustKmh) },
        { label: "PRECIP", icon: "umbrella", value: root.num(root.detail.precipProbability), unit: "%",
          sub: Fmt.millimetres(root.detail.precipMm) + " mm expected" },
        root.showPressure
            ? { label: "PRESSURE", icon: "gauge", value: root.num(root.detail.pressureHpa), unit: "hPa", sub: "" }
            : { label: "UV INDEX", icon: "sun", value: root.num(root.detail.uvIndex), unit: "/ 11",
                sub: (root.detail.uvLabel || "") + (root.detail.uvIndex >= 6 ? " · cover up midday" : "") }
    ]

    Repeater {
        model: root.cells

        Rectangle {
            id: cell
            color: Theme.card

            required property var modelData
            required property int index

            readonly property real cellHeight: (root.height - 3) / 4
            y: index * (cellHeight + 1)
            width: root.width
            height: cellHeight

            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                height: 24 + 6 + 14

                Row {
                    y: 0
                    height: 24
                    spacing: 7

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: cell.modelData.icon
                        size: 12
                        strokeWidth: 1.6
                        color: Theme.accentLight
                    }
                    MonoText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cell.modelData.label
                        color: Theme.accentLight
                        font.letterSpacing: 1.26
                    }
                }

                Row {
                    anchors.right: parent.right
                    y: 2
                    height: 24
                    spacing: 4

                    CondensedText {
                        id: value
                        anchors.baseline: unit.baseline
                        text: cell.modelData.value
                        font.pixelSize: 26
                        font.letterSpacing: -0.52
                    }
                    MonoText {
                        id: unit
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 4
                        width: Math.max(22, implicitWidth)
                        text: cell.modelData.unit
                    }
                }

                CondensedText {
                    y: 24 + 6
                    x: 19
                    text: cell.modelData.sub
                    font.pixelSize: 12
                    color: Theme.dim
                }
            }
        }
    }
}
