pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

/**
 * Total CPU load in percent, from /proc/stat. This is the one place that
 * reads it for the Home rings (SystemUsage) and the auto power profile
 * (AutoPowerProfile). It samples only while someone needs it: a visible
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

    signal measured(real percent)

    property double previousIdle: -1
    property double previousTotal: -1

    // Without a timer running, the next sample has no earlier one to compare to.
    onActiveChanged: {
        if (!active) {
            previousIdle = -1;
            previousTotal = -1;
        }
    }

    Process {
        id: statReader
        command: ["head", "-n", "1", "/proc/stat"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.readSample(text)
        }
    }

    /** Turns one "/proc/stat" cpu line into the load since the last sample. */
    function readSample(line) {
        var fields = line.trim().split(/\s+/).slice(1).map(Number);
        if (fields.length < 4) return;

        var idle = fields[3] + (fields[4] || 0);
        var total = fields.reduce(function (a, b) { return a + b; }, 0);

        if (root.previousTotal >= 0) {
            var totalDelta = total - root.previousTotal;
            var idleDelta = idle - root.previousIdle;
            if (totalDelta > 0) {
                root.percent = Math.max(0, Math.min(100, 100 * (totalDelta - idleDelta) / totalDelta));
                root.measured(root.percent);
            }
        }
        root.previousIdle = idle;
        root.previousTotal = total;
    }

    Timer {
        interval: root.sampleIntervalMs
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: statReader.running = true
    }
}
