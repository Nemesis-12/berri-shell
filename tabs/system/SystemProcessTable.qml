import QtQuick
import qs.common
import qs.services

/**
 * Process table of the system tab: a header row and a scrolling list
 * of the busiest processes (SystemStats.processes).
 * The tab sets `x` and `y`.
 */
Rectangle {
    id: root

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
        x: root.width - 216
        mono: true
        lineTop: 9
        font.pixelSize: 9
        font.letterSpacing: 9 * 0.14
        color: Theme.dim
        text: "CPU"
    }

    SystemText {
        x: root.width - 16 - width
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
