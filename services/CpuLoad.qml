pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/SystemReadings.js" as Readings

/**
 * Total and per-core CPU load from one /proc/stat read. It samples while a visible
 * view (`viewers` > 0) or the auto power profile (`autoProfileOn`). A
 * visible view gets a sample every 2.5 s; the auto profile alone needs one
 * every 5 s. `measured` fires after each new sample.
 */
Singleton {
    id: root

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    /** True while the auto power profile is the power mode in use. */
    property bool autoProfileOn: false

    readonly property bool active: viewers > 0 || autoProfileOn
    readonly property int sampleIntervalMs: viewers > 0 ? 2500 : 5000

    /** Load in percent between the last two samples. */
    property real percent: 0
    property var coreLoads: []
    property int threadCount: 0
    property var coreGroups: []
    property bool topologyRead: false

    signal measured(real percent)

    property var previousCounters: null

    // Without a timer running, the next sample has no earlier one to compare to.
    onActiveChanged: {
        if (!active) previousCounters = null;
        else if (!topologyRead) topologyReader.running = true;
    }

    Process {
        id: topologyReader
        command: ["sh", Quickshell.shellPath("scripts/system-hardware.sh"), "cores"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.coreGroups = Readings.readCoreGroups(text);
                root.topologyRead = true;
                if (root.active) root.readSample(statFile.text());
            }
        }
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: if (root.active) root.readSample(text())
    }

    // Publishes total and core load from the same completed /proc/stat sample.
    function readSample(text) {
        var sample = Readings.readCpuLoad(text, previousCounters, coreGroups);
        if (!sample) return;
        previousCounters = sample.counters;
        threadCount = sample.threadCount;
        coreLoads = sample.coreLoads;
        if (sample.percent === null) return;
        percent = sample.percent;
        measured(percent);
    }

    Timer {
        interval: root.sampleIntervalMs
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: statFile.reload()
    }
}
