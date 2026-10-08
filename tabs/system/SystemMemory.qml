import QtQuick
import qs.common
import qs.services

/**
 * Memory card of the system tab: used and total RAM with a meter, and
 * swap with a small meter.
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
