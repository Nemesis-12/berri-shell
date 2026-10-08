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
    Rectangle {
        id: processTable
        x: 0
        y: 151
        width: 496
        height: 177
        color: Theme.card
        clip: true

        SystemText {
            x: 16
            mono: true
            lineTop: 9
            font.pixelSize: 9
            font.letterSpacing: 9 * 0.14
            color: Theme.dim
            text: "PROCESS"
        }

        SystemText {
            x: processTable.width - 216
            mono: true
            lineTop: 9
            font.pixelSize: 9
            font.letterSpacing: 9 * 0.14
            color: Theme.dim
            text: "CPU"
        }

        SystemText {
            x: processTable.width - 16 - width
            mono: true
            lineTop: 9
            font.pixelSize: 9
            font.letterSpacing: 9 * 0.14
            color: Theme.dim
            text: "MEM"
        }

        Rectangle {
            y: 27
            width: parent.width
            height: 1
            color: Theme.border
        }

        Flickable {
            id: list
            y: 28
            width: parent.width
            height: parent.height - 28
            contentHeight: SystemStats.processes.length * 29
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Repeater {
                model: SystemStats.processes

                SystemProcessRow {
                    required property var modelData
                    required property int index

                    y: index * 29
                    width: list.width
                    name: modelData.name
                    cpu: modelData.cpu
                    mem: modelData.mem
                }
            }
        }

        // Scroll thumb, shown only when the list is taller than its window.
        ListScrollBar {
            view: list
            thickness: 6
            onlyWhileMoving: false
            viewTop: list.y
            x: parent.width - 6
        }
    }

    // ---- Memory ----
    Rectangle {
        x: 497
        y: 151
        width: 240
        height: 88
        color: Theme.card

        SideLabel {
            x: 12
            y: 76 - height
            width: 9
            textX: 7.875 - textBaseline
            text: "MEMORY"
        }

        SystemText {
            id: ramNumber
            x: 33
            lineTop: 12
            lineBox: 0.85
            font.pixelSize: 36
            text: SystemStats.ramUsedGb.toFixed(1)
        }

        SystemText {
            x: ramNumber.x + ramNumber.width + 6
            mono: true
            lineTop: 32
            font.pixelSize: 10
            color: Theme.dim
            text: "/ " + Math.round(SystemStats.ramTotalGb) + " GB"
        }

        SystemMeter {
            x: 33
            y: 51.8
            width: 191
            height: 6
            value: SystemStats.ramTotalGb > 0 ? SystemStats.ramUsedGb / SystemStats.ramTotalGb : 0
        }

        SystemText {
            id: swapLabel
            x: 33
            mono: true
            lineTop: 67
            font.pixelSize: 9
            font.letterSpacing: 9 * 0.1
            color: Theme.dim
            text: "SWAP"
        }

        SystemText {
            id: swapValue
            x: 224 - width
            mono: true
            lineTop: 67
            font.pixelSize: 9
            color: Theme.dim
            text: SystemStats.swapUsedGb.toFixed(1) + " / " + Math.round(SystemStats.swapTotalGb)
        }

        SystemMeter {
            x: swapLabel.x + swapLabel.width + 8
            y: 70
            width: swapValue.x - 8 - x
            height: 3
            value: SystemStats.swapTotalGb > 0 ? SystemStats.swapUsedGb / SystemStats.swapTotalGb : 0
        }
    }

    // ---- Disks ----
    Rectangle {
        x: 497
        y: 240
        width: 240
        height: 88
        color: Theme.card

        SideLabel {
            x: 12
            y: 76 - height
            width: 9
            textX: 7.875 - textBaseline
            text: "DISKS"
        }

        Repeater {
            model: SystemStats.disks

            Item {
                id: disk
                required property var modelData
                required property int index

                readonly property real rowY: index === 0 ? 15 : 47

                SystemText {
                    id: mountName
                    x: 33
                    lineTop: disk.rowY
                    font.pixelSize: 15
                    text: disk.modelData.mount + " "
                }

                SystemText {
                    id: deviceName
                    x: mountName.x + mountName.width
                    visible: x + width + 10 < diskSize.x
                    mono: true
                    lineTop: disk.rowY + 5
                    font.pixelSize: 9
                    color: Theme.dim
                    text: disk.modelData.device.toUpperCase()
                }

                SystemText {
                    id: diskSize
                    x: 224 - width
                    mono: true
                    lineTop: disk.rowY + 5
                    font.pixelSize: 10
                    color: Theme.dim
                    text: Fmt.usedOfTotal(disk.modelData.usedGb, disk.modelData.totalGb)
                }

                SystemMeter {
                    x: 33
                    y: disk.rowY + 20
                    width: 191
                    height: 6
                    value: disk.modelData.percent / 100
                }
            }
        }
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
