import QtQuick
import Quickshell.Services.UPower
import qs.common

/**
 * Battery cell: level, charging state and time left from UPower, a 3px
 * level bar, and the 4 power-mode buttons (saver/balanced/performance/auto)
 * that read and set PowerModes' saved choice for the current power source.
 * Mirrors the mock's 5C battery cell (Berri Dashboard v2.dc.html, ~line 346).
 * The low-battery notification comes from LowBatteryAlert, not this cell.
 */
Item {
    id: root

    /** Top-level item the power-mode buttons' tooltips reparent into. */
    property Item tooltipLayer: null

    readonly property var device: UPower.displayDevice
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property int state: device ? device.state : UPowerDeviceState.Unknown

    /** "10H 24M LEFT" / "1H 20M TO FULL" / "FULL" / "" (time unknown). */
    readonly property string timeLabel: {
        if (!device) return "";
        if (state === UPowerDeviceState.Charging && device.timeToFull > 0)
            return formatDuration(device.timeToFull) + " TO FULL";
        if (state === UPowerDeviceState.FullyCharged || (!UPower.onBattery && percent >= 100))
            return "FULL";
        if (state === UPowerDeviceState.Discharging && device.timeToEmpty > 0)
            return formatDuration(device.timeToEmpty) + " LEFT";
        return "";
    }

    readonly property string suffixText: timeLabel.length > 0 ? ("% · " + timeLabel) : "%"

    function formatDuration(seconds) {
        var totalMinutes = Math.round(seconds / 60);
        var h = Math.floor(totalMinutes / 60);
        var m = totalMinutes % 60;
        return h + "H " + m + "M";
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        // Number row: fixed-height box (matches the mock's tight, line-height-.9
        // row) so the glyph sits near the row's top instead of leaving the
        // font's natural ascent leading as dead space above it.
        Item {
            id: numberRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 29

            Text {
                textFormat: Text.PlainText
                id: levelNumber
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.percent
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 32
                lineHeight: 0.9
                color: Theme.fg
            }

            MonoText {
                anchors.left: levelNumber.right
                anchors.leftMargin: 6
                anchors.baseline: levelNumber.baseline
                text: root.suffixText
                font.pixelSize: 10
                font.letterSpacing: 0.8
            }
        }

        // Level bar: track + fill, width animates smoothly with the level.
        Rectangle {
            id: levelTrack
            anchors.top: numberRow.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            height: 3
            color: Theme.border

            Rectangle {
                height: parent.height
                width: parent.width * root.percent / 100
                color: Theme.accent

                Behavior on width {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.standardCurve
                    }
                }
            }
        }

        // Power-mode buttons: saver, balanced, performance, auto.
        Item {
            id: modesRow
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28

            readonly property int gap: 4
            readonly property real buttonWidth: (width - 3 * gap) / 4
            readonly property var modes: [
                { key: "saver", icon: "leaf", tooltip: "Power saver" },
                { key: "balanced", icon: "contrast", tooltip: "Balanced" },
                { key: "performance", icon: "zap", tooltip: "Performance" },
                { key: "auto", icon: "circle-gauge", tooltip: "Auto · adjusts to load" }
            ]

            Repeater {
                model: modesRow.modes

                delegate: Rectangle {
                    id: modeButton
                    required property var modelData
                    required property int index

                    readonly property bool active: PowerModes.activeMode === modelData.key

                    x: index * (modesRow.buttonWidth + modesRow.gap)
                    y: 0
                    width: modesRow.buttonWidth
                    height: modesRow.height
                    radius: 3
                    border.width: 1
                    border.color: active ? Theme.accentLine : Theme.border
                    color: active ? Theme.accentFill : Theme.raised

                    ColorFade on color { duration: Theme.stateMs }
                    ColorFade on border.color { duration: Theme.stateMs }

                    Icon {
                        anchors.centerIn: parent
                        name: modeButton.modelData.icon
                        size: 15
                        strokeWidth: 1.5
                        color: modeButton.active ? Theme.accentLight
                            : (hoverHandler.hovered ? Theme.fg2 : Theme.dim)

                        ColorFade on color { duration: Theme.stateMs }
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerModes.setMode(modeButton.modelData.key)
                    }

                    Tooltip {
                        anchorItem: modeButton
                        overlayItem: root.tooltipLayer
                        hovered: hoverHandler.hovered && root.tooltipLayer !== null
                        text: modeButton.modelData.tooltip
                    }
                }
            }
        }
    }
}
