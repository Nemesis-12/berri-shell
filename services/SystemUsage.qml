pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/MemoryUse.js" as MemoryUse
import "../logic/SystemReadings.js" as Readings
import qs.services

/** Shared disk, memory and uptime snapshots for Home and System, sampled while visible. */
Singleton {
    id: root

    readonly property int sampleIntervalMs: 2500
    property int viewers: 0
    readonly property real cpuPercent: CpuLoad.percent

    property var memory: null
    property var disks: []
    property real uptimeSeconds: 0
    readonly property var rootDisk: disks.filter(function (disk) { return disk.mount === "/"; })[0] || null
    readonly property real ramPercent: memory ? memory.percent : 0
    readonly property real ramUsedGb: memory ? memory.usedGb : 0
    readonly property real ramTotalGb: memory ? memory.totalGb : 0
    readonly property real swapUsedGb: memory ? memory.swapUsedGb : 0
    readonly property real swapTotalGb: memory ? memory.swapTotalGb : 0
    readonly property real diskPercent: rootDisk ? rootDisk.percent : 0
    readonly property real diskUsedGb: rootDisk ? rootDisk.usedGb : 0

    FileView {
        id: memoryFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: if (root.viewers > 0) root.readMemory(text())
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: if (root.viewers > 0) root.readUptime(text())
    }

    Process {
        id: diskReader
        command: ["df", "-P", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (root.viewers > 0) root.readDisk(text)
        }
    }

    // Publishes one memory snapshot so percent and sizes change together.
    function readMemory(text) {
        var next = MemoryUse.readMemoryUse(text);
        if (next) memory = next;
    }

    // Both views use the same parsed disk sizes and percentage.
    function readDisk(text) {
        disks = Readings.readDisks(text);
    }

    // Both uptime captions use one completed /proc/uptime sample.
    function readUptime(text) {
        var seconds = Readings.readUptime(text);
        if (seconds !== null) uptimeSeconds = seconds;
    }

    onViewersChanged: if (viewers === 0) diskReader.running = false

    Timer {
        interval: root.sampleIntervalMs
        running: root.viewers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: { memoryFile.reload(); uptimeFile.reload(); }
    }

    Timer {
        interval: 30000
        running: root.viewers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!diskReader.running) diskReader.running = true
    }
}
