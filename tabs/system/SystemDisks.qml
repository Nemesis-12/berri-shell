import QtQuick
import "../../logic/SystemFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Disks card of the system tab: up to two mounts, each with device, size
 * and a usage meter.
 * The tab sets `x` and `y`.
 */
Rectangle {
    id: root

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
