import QtQuick
import qs.services
import qs.common

import "../../logic/SystemFormat.js" as Fmt

/** One process row: name, CPU bar with value, memory value. The row lights up under the pointer. */
Item {
    id: root

    property string name: ""
    /** CPU share in percent, or null until two samples exist. */
    property var cpu: null
    property real mem: 0
    /** Number of threads used to measure the whole CPU share. */
    property int threadCount: SystemStats.threadCount

    height: 29

    HoverHandler { id: hover }

    Rectangle {
        width: parent.width
        height: 28
        color: Theme.raised
        opacity: hover.hovered ? 1 : 0

        Fade on opacity {}
    }

    Rectangle {
        y: 28
        width: parent.width
        height: 1
        color: Theme.border
    }

    SystemText {
        x: 16
        lineTop: 6.5
        font.pixelSize: 15
        text: root.name
        width: root.width - 246
        elide: Text.ElideRight
    }

    SystemMeter {
        x: root.width - 216
        y: 9
        width: 92
        height: 10
        color: Theme.raised
        value: (root.cpu || 0) * Math.max(1, root.threadCount) * 4 / 100
    }

    SystemText {
        x: root.width - 116
        mono: true
        lineTop: 9
        font.pixelSize: 10
        text: Fmt.processCpu(root.cpu)
        color: (root.cpu || 0) > 20 / Math.max(1, root.threadCount) ? Theme.accentLight : Theme.fg2
    }

    SystemText {
        x: root.width - 16 - width
        mono: true
        lineTop: 9
        font.pixelSize: 10
        text: root.mem.toFixed(1) + "%"
        color: root.mem > 10 ? Theme.accentLight : Theme.fg2
    }
}
