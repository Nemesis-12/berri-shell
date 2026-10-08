import QtQuick
import "../../logic/PixelGrid.js" as PixelGrid
import "../../logic/SystemFormat.js" as Fmt
import "../../logic/Times.js" as Times
import qs.common
import qs.services

/**
 * System tab body (mock 5C SPINE, Berri System v2.dc.html), 737 x 452:
 * CPU readout and detected core meters on top, process table beside memory
 * and disks in the middle, network and three sensor tiles below, and a
 * system line at the bottom. 1px gaps show the Theme.border backdrop. Live
 * numbers come from SystemStats, which samples only while this tab is
 * visible. The mock's SPEED TEST button is left out: no real source.
 */
Item {
    id: root

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)
    WhileVisible { service: SystemStats }
    WhileVisible { service: CpuLoad }

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // ---- CPU readout ----
    Rectangle {
        x: 0
        y: 0
        width: 240
        height: 150
        color: Theme.card

        SideLabel {
            x: 12
            y: 136 - height
            width: 9
            textX: 7.875 - textBaseline
            text: "CPU"
        }

        SystemText {
            id: cpuNumber
            x: 33
            lineTop: 14
            lineBox: 0.78
            font.pixelSize: 96
            font.letterSpacing: -96 * 0.04
            text: Math.round(SystemStats.cpuPercent)
        }

        SystemText {
            x: cpuNumber.x + cpuNumber.width + 4
            mono: true
            lineTop: 73
            font.pixelSize: 16
            color: Theme.dim
            text: "%"
        }

        Row {
            x: 33
            spacing: 14

            SystemText {
                mono: true
                lineTop: 125.5
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.06
                color: Theme.dim
                text: Fmt.sensor(SystemStats.cpuGhz, " GHZ", 2)
            }

            SystemText {
                mono: true
                lineTop: 125.5
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.06
                color: Theme.dim
                text: Fmt.sensor(SystemStats.cpuTempC, "°C", 0)
            }
        }
    }

    // ---- Per-core meters ----
    Repeater {
        model: SystemStats.coreLoads.length

        SystemCore {
            required property int index

            readonly property real slot: (496 + 1) / SystemStats.coreLoads.length
            x: PixelGrid.snap(241 + index * slot, root.dpr)
            y: 0
            width: PixelGrid.snap(241 + (index + 1) * slot - 1, root.dpr) - x
            height: 150
            core: index
            load: SystemStats.coreLoads[index] || 0
        }
    }

    // ---- Process table ----
    SystemProcessTable {
        x: 0
        y: 151
    }

    // ---- Memory ----
    SystemMemory {
        x: 497
        y: 151
    }

    // ---- Disks ----
    SystemDisks {
        x: 497
        y: 240
    }

    // ---- Network ----
    Rectangle {
        x: 0
        y: 329
        width: 240
        height: 86
        color: Theme.card

        SideLabel {
            x: 12
            y: 74 - height
            width: 9
            textX: 7.875 - textBaseline
            text: SystemStats.netName.toUpperCase()
        }

        Row {
            x: 33
            spacing: 18

            Row {
                spacing: 5

                SystemText {
                    mono: true
                    lineTop: 65
                    font.pixelSize: 9
                    color: Theme.accentLight
                    text: "DN"
                }

                SystemText {
                    lineTop: 48.4
                    lineBox: 0.8
                    font.pixelSize: 32
                    text: Fmt.rate(SystemStats.downMBs)
                }

                SystemText {
                    mono: true
                    lineTop: 65
                    font.pixelSize: 9
                    color: Theme.dim
                    text: "MB/S"
                }
            }

            Row {
                spacing: 5

                SystemText {
                    mono: true
                    lineTop: 65
                    font.pixelSize: 9
                    color: Theme.accentLight
                    text: "UP"
                }

                SystemText {
                    lineTop: 48.4
                    lineBox: 0.8
                    font.pixelSize: 32
                    text: Fmt.rate(SystemStats.upMBs)
                }

                SystemText {
                    mono: true
                    lineTop: 65
                    font.pixelSize: 9
                    color: Theme.dim
                    text: "MB/S"
                }
            }
        }
    }

    // ---- Sensor tiles ----
    Repeater {
        model: [
            { label: "CPU TEMP", value: Fmt.sensor(SystemStats.cpuTempC, "°", 0) },
            { label: "GPU TEMP", value: Fmt.sensor(SystemStats.gpuTempC, "°", 0) },
            { label: "FAN RPM", value: Fmt.sensor(SystemStats.fanRpm, "", 0) }
        ]

        Rectangle {
            required property var modelData
            required property int index

            readonly property real slot: (496 - 2) / 3 + 1
            x: PixelGrid.snap(241 + index * slot, root.dpr)
            y: 329
            width: PixelGrid.snap(241 + (index + 1) * slot - 1, root.dpr) - x
            height: 86
            color: Theme.card

            SystemText {
                x: 14
                mono: true
                lineTop: 12
                font.pixelSize: 9
                font.letterSpacing: 9 * 0.14
                color: Theme.dim
                text: modelData.label
            }

            SystemText {
                x: 14
                lineTop: 42
                lineBox: 0.8
                font.pixelSize: 40
                font.letterSpacing: -40 * 0.02
                text: modelData.value
            }
        }
    }

    // ---- System line ----
    Rectangle {
        x: 0
        y: 416
        width: parent.width
        height: parent.height - 416
        color: Theme.card

        Row {
            x: 16
            spacing: 16

            SystemText {
                mono: true
                lineTop: 12.5
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.06
                color: Theme.fg2
                text: SystemStats.hostName.toUpperCase()
            }

            SystemText {
                mono: true
                lineTop: 12.5
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.06
                color: Theme.dim
                text: SystemStats.kernelName.toUpperCase()
            }

            SystemText {
                mono: true
                lineTop: 12.5
                font.pixelSize: 10
                font.letterSpacing: 10 * 0.06
                color: Theme.dim
                text: "UP " + Times.duration(SystemStats.uptimeSeconds)
            }
        }

        SystemText {
            x: parent.width - 16 - width
            mono: true
            lineTop: 12.5
            font.pixelSize: 10
            font.letterSpacing: 10 * 0.06
            color: Theme.fg2
            text: SystemStats.distroName.toUpperCase()
        }
    }
}
