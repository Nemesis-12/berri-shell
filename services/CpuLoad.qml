pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
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
    property var coreLoads: [0, 0, 0, 0, 0, 0, 0, 0]
    property int threadCount: 1

    signal measured(real percent)

    property var previousCounters: null

    // Without a timer running, the next sample has no earlier one to compare to.
    onActiveChanged: {
        if (!active) previousCounters = null;
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: if (root.active) root.readSample(text())
    }

    function readSample(text) {
        var sample = Readings.readCpuLoad(text, previousCounters);
        if (!sample) return;
        previousCounters = sample.counters;
        threadCount = Math.max(1, sample.threadCount);
        if (sample.percent === null) return;
        percent = sample.percent;
        coreLoads = sample.coreLoads;
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
