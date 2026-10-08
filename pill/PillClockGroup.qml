import QtQuick
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/Timeline.js" as Timeline
import qs.common
import qs.services

/**
 * Clock, date, weather and tray of the pill, as one group. The clock sits at
 * a fixed, rounded center so it never moves while the pill's width animates;
 * date, weather and tray anchor off its edges (not a layout row) so nothing
 * snaps to a fractional pixel each frame. The group is hidden while the
 * dashboard opens, is open or closes, and shown at rest. Date, weather and
 * tray reveal on `hovered`. The pill sets the timeline values; clicks on
 * tray icons go to `trayLayers`.
 */
Item {
    id: root

    /** True while the pointer reveals date, weather and tray. */
    required property bool hovered
    /** True while a notification card covers the pill; the clock fades out under it. */
    required property bool popupActive
    /** False while the whole pill is faded out. */
    required property bool pillShown
    required property real dpr
    required property real elapsedMs
    required property bool closing
    required property int clockFadeMs
    required property int clockCloseAtMs
    required property var trayItems
    required property PillTrayLayers trayLayers

    // The shared minute clock ticks only while this group shows.
    visible: opacity > 0.001 && root.pillShown
    WhileVisible { service: Clock }

    // A notification card covers the pill: the clock fades out under it.
    // States/Transitions, not a Behavior: the fade in has a delay.
    property real uncovered: 1
    state: root.popupActive ? "covered" : "clear"
    states: [
        State { name: "clear"; PropertyChanges { target: root; uncovered: 1 } },
        State { name: "covered"; PropertyChanges { target: root; uncovered: 0 } }
    ]
    transitions: [
        Transition {
            from: "covered"; to: "clear"
            SequentialAnimation {
                PauseAnimation { duration: 160 }
                NumberAnimation { target: root; property: "uncovered"; duration: 240 }
            }
        },
        Transition {
            from: "clear"; to: "covered"
            NumberAnimation { target: root; property: "uncovered"; duration: 140 }
        }
    ]

    opacity: uncovered * (1 - Timeline.fadeSlice(root.elapsedMs, 0, root.clockFadeMs, root.closing, root.clockCloseAtMs))

    // Clock: auto width, fixed at the pill's rounded center.
    Text {
        textFormat: Text.PlainText
        id: clockText
        x: PixelGrid.snap((parent.width - width) / 2, root.dpr)
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(Clock.minute, "h:mm AP")
        font.family: Theme.condensed
        font.weight: Font.Medium
        font.pixelSize: 15
        font.letterSpacing: -0.15
        color: Theme.fg
    }

    // Date: right-aligned against the clock's left edge.
    Text {
        textFormat: Text.PlainText
        id: dateText
        anchors.right: clockText.left
        anchors.rightMargin: 10
        anchors.verticalCenter: clockText.verticalCenter
        text: Qt.formatDateTime(Clock.minute, "ddd d")
        font.family: Theme.mono
        font.weight: Font.Medium
        font.pixelSize: 10
        color: Theme.dim
        opacity: root.hovered ? 1 : 0
        Fade on opacity { duration: Theme.stateMs }

        transform: Translate {
            x: root.hovered ? 0 : 8
            Behavior on x {
                SpringMotion {
                    duration: 500
                }
            }
        }
    }

    // Weather icon + temperature: left-aligned against the clock's right edge.
    Row {
        id: weatherRow
        anchors.left: clockText.right
        anchors.leftMargin: 10
        anchors.verticalCenter: clockText.verticalCenter
        spacing: 5
        opacity: root.hovered ? 1 : 0
        Fade on opacity { duration: Theme.stateMs }

        transform: Translate {
            x: root.hovered ? 0 : -8
            Behavior on x {
                SpringMotion {
                    duration: 500
                }
            }
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: Weather.iconName
            size: 14
            strokeWidth: 1.5
            color: Theme.dim
        }

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.ready ? Weather.temperatureC + "°" : "--°"
            font.family: Theme.mono
            font.weight: Font.Medium
            font.pixelSize: 10
            color: Theme.dim
        }
    }

    // Tray: after the weather, same reveal motion (fade + slide in from the left).
    PillTray {
        id: trayRow
        anchors.left: weatherRow.right
        anchors.leftMargin: 8
        anchors.verticalCenter: clockText.verticalCenter
        items: root.trayItems
        menuItem: root.trayLayers.menuItem
        gridOpen: root.trayLayers.gridOpen
        flashItem: root.trayLayers.flashItem
        enabled: root.hovered
        opacity: root.hovered ? 1 : 0
        Fade on opacity { duration: Theme.stateMs }

        transform: Translate {
            x: root.hovered ? 0 : -8
            Behavior on x {
                SpringMotion {
                    duration: 500
                }
            }
        }

        onActivated: (item, button) => root.trayLayers.activate(item, button)
        onMenuRequested: (item, button) => root.trayLayers.openMenu(item, button)
        onMoreClicked: (chip) => root.trayLayers.toggleGrid(chip)
    }
}
