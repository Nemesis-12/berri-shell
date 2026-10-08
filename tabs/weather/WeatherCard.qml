import QtQuick
import "../../logic/WeatherFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Current conditions card for one day (mock 5C, first cell, 300x272):
 * side label, location, update time, refresh, big temperature, condition
 * icon, condition, feels like / high / low and sunrise / sunset.
 * Day 0 is now; later days show that day's forecast. While the last refresh
 * failed (`Weather.error`), the temperature and condition icon turn dim and
 * a StaleChip with the data age replaces the update time.
 */
Item {
    id: root

    /** Day index: 0 is now. */
    property int day: 0
    property bool clock24: false

    readonly property var detail: Weather.dayDetail(root.day) || ({})
    readonly property bool isNow: root.day === 0
    /** True while the last refresh failed: the readout turns dim and a chip shows the age. */
    readonly property bool stale: Weather.error !== ""
    readonly property bool byDay: root.detail.isDay === undefined ? (root.isNow ? Weather.isDay : true) : root.detail.isDay
    readonly property string group: Weather.weatherGroup(root.detail.code === undefined ? 3 : root.detail.code)
    readonly property bool hasFeelsLike: root.detail.feelsLikeC !== undefined && root.detail.feelsLikeC !== null

    function whenLabel() {
        if (root.isNow) return "NOW";
        var date = Fmt.toDate(Weather.days[root.day].date);
        return Fmt.weekday(date) + " " + date.getDate();
    }

    function temp(v) {
        return v === undefined || v === null ? "--" : Math.round(v).toString();
    }

    SideLabel {
        tone: Theme.accentLight
        renderType: Text.CurveRendering
        x: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        text: root.whenLabel()
    }

    Item {
        x: 12 + 9 + 10
        y: 16 + 2
        width: parent.width - x - 16
        height: parent.height - 16 - y

        Column {
            id: head
            y: 0
            spacing: 6

            MonoText {
                text: (Weather.locationName || "").toUpperCase()
                color: Theme.accentLight
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }
            MonoText {
                visible: !root.stale
                text: Weather.updatedAt > 0 ? "Updated " + Fmt.clock(Weather.updatedAt, root.clock24) : ""
            }
            StaleChip {}
        }

        Rectangle {
            id: refresh
            anchors.right: parent.right
            width: 26
            height: 26
            color: Theme.raised

            property real turns: 0

            Connections {
                target: Weather
                function onLoadingChanged() {
                    if (Weather.loading) refresh.turns += 360;
                }
            }

            Icon {
                id: refreshIcon
                anchors.centerIn: parent
                name: "refresh-ccw"
                size: 13
                strokeWidth: 1.8
                color: refreshArea.containsMouse ? Theme.fg : Theme.dim
                rotation: refresh.turns

                ColorFade on color {}
                Behavior on rotation {
                    EmphasizedMotion {
                        duration: 700
                    }
                }
            }

            MouseArea {
                id: refreshArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Weather.refresh()
            }
        }

        Item {
            id: tempRow
            anchors.left: parent.left
            anchors.leftMargin: -4
            anchors.right: parent.right
            height: 100
            y: (head.y + head.height + bottom.y - height) / 2

            CondensedText {
                id: big
                text: root.temp(root.detail.tempC)
                color: root.stale ? Theme.dim : Theme.fg
                Behavior on color { StandardColorMotion { duration: Theme.stateMs } }
                font.pixelSize: 128
                font.letterSpacing: -5.12
                x: -2
                y: -34
            }
            CondensedText {
                x: big.width + 0.5
                y: -10.5
                text: "°"
                color: Theme.dim
                font.pixelSize: 30
            }
            Icon {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                name: Weather.iconForGroup(root.group, root.byDay)
                size: 48
                strokeWidth: 1.4
                color: root.stale ? Theme.dim : Theme.accentLight
                Behavior on color { StandardColorMotion { duration: Theme.stateMs } }
            }
        }

        Column {
            id: bottom
            anchors.bottom: parent.bottom
            spacing: 8

            CondensedText {
                text: Weather.labelForGroup(root.group)
                font.pixelSize: 22
            }
            MonoText {
                text: (root.hasFeelsLike ? "Feels like " + root.temp(root.detail.feelsLikeC) + "° · " : "")
                    + "H " + root.temp(root.detail.maxC) + "° L " + root.temp(root.detail.minC) + "°"
                color: Theme.accentLight
                font.letterSpacing: 0.54
                font.capitalization: Font.AllUppercase
            }
            Row {
                topPadding: 2
                spacing: 14

                Row {
                    spacing: 5
                    Icon { name: "sunrise"; size: 12; strokeWidth: 1.8; color: Theme.accentLight }
                    MonoText { text: Fmt.clock(root.detail.sunrise, root.clock24); color: Theme.accentLight }
                }
                Row {
                    spacing: 5
                    Icon { name: "sunset"; size: 12; strokeWidth: 1.8; color: Theme.accentLight }
                    MonoText { text: Fmt.clock(root.detail.sunset, root.clock24); color: Theme.accentLight }
                }
            }
        }
    }
}
