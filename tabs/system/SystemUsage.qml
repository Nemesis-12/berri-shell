pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../logic/MemoryUse.js" as MemoryUse
import qs.common
import qs.services

/**
 * Numbers for the Home usage rings. CPU percent comes from CpuLoad. RAM
 * used percent comes from /proc/meminfo (parsed by MemoryUse.js) and disk used
 * percent of / from `df`. Nothing runs until a view is visible (`viewers` > 0):
 * then one shell process every sampleIntervalMs reads both sources.
 */
Singleton {
    id: root

    readonly property int sampleIntervalMs: 2500

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    readonly property real cpuPercent: CpuLoad.percent
    property real ramPercent: 0
    property real diskPercent: 0

    // Used, in GB, for the ring captions (1 decimal for RAM, whole GB for disk).
    property real ramUsedGb: 0
    property real diskUsedGb: 0

    Process {
        id: sampleReader
        command: ["sh", "-c", "cat /proc/meminfo; echo @@DISK@@; df -P /"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.readSample(text)
        }
    }

    function readSample(text) {
        var parts = text.split("@@DISK@@\n");
        root.readMemory(parts[0] || "");
        root.readDisk(parts[1] || "");
    }

    /** Updates ramPercent and ramUsedGb from a "/proc/meminfo" dump. */
    function readMemory(block) {
        var memoryUse = MemoryUse.readMemoryUse(block);
        if (!memoryUse) return;
        root.ramPercent = memoryUse.percent;
        root.ramUsedGb = Math.round(memoryUse.usedGb * 10) / 10;
    }

    /** Updates diskPercent and diskUsedGb from `df -P /`'s data line (1K blocks). */
    function readDisk(block) {
        var lines = block.trim().split("\n");
        if (lines.length < 2) return;
        var fields = lines[1].trim().split(/\s+/);
        if (fields.length < 4) return;
        root.diskUsedGb = Math.round(Number(fields[2]) / 1024 / 1024);
        var match = lines[1].match(/(\d+)%/);
        if (match) root.diskPercent = Number(match[1]);
    }

    Timer {
        interval: root.sampleIntervalMs
        running: root.viewers > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: sampleReader.running = true
    }
}
