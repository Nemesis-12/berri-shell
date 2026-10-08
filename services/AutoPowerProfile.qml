pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * Decides the power profile for "auto" mode from sustained CPU load.
 * Takes the load from CpuLoad (a sample every 5 s or faster) and keeps a moving
 * average over the last averageWindowMs (2 minutes). A switch only happens once
 * that average has stayed on one side of a threshold for the matching
 * sustain window, and the same window is used to leave the state again.
 * Performance needs sustained high load; power-saver needs sustained low
 * load AND running on battery; otherwise the profile is balanced. After any
 * switch, holds for switchCooldownMs before switching again.
 * CpuLoad samples for this singleton only while auto is the power mode in
 * use; when auto is off, the average and the sustain windows start again.
 */
Singleton {
    id: root

    readonly property int averageWindowMs: 2 * 60 * 1000
    readonly property real highLoadThreshold: 70           // percent
    readonly property real lowLoadThreshold: 25            // percent
    readonly property int highSustainMs: 2 * 60 * 1000     // to enter/leave performance
    readonly property int lowSustainMs: 5 * 60 * 1000      // to enter/leave power-saver
    readonly property int switchCooldownMs: 10 * 60 * 1000

    /** Final decision for "auto" mode: a PowerProfile.Enum value. */
    readonly property int profile: appliedProfile

    property int appliedProfile: PowerProfile.Balanced
    property double lastSwitchTime: 0

    /** True while auto is the power mode in use. */
    readonly property bool autoModeOn: PowerModes.activeMode === "auto"

    /** [{ time, load }] samples inside the average window. */
    property var loadSamples: []
    property real movingAverage: 0

    // Debounced (sustained) state of each threshold comparison.
    property bool highSide: false
    property double highSideSince: 0
    property bool highDebounced: false

    property bool lowSide: false
    property double lowSideSince: 0
    property bool lowDebounced: false

    Binding {
        target: CpuLoad
        property: "autoProfileOn"
        value: root.autoModeOn
    }

    onAutoModeOnChanged: {
        if (autoModeOn) return;
        loadSamples = [];
        movingAverage = 0;
        highSide = false; highSideSince = 0; highDebounced = false;
        lowSide = false; lowSideSince = 0; lowDebounced = false;
    }

    Connections {
        target: CpuLoad
        function onMeasured(percent) {
            if (root.autoModeOn) root.pushSample(percent);
        }
    }

    function pushSample(load) {
        var now = Date.now();
        var recentLoads = root.loadSamples.concat([{ time: now, load: load }])
            .filter(function (sample) { return now - sample.time <= root.averageWindowMs; });
        root.loadSamples = recentLoads;

        var totalLoad = recentLoads.reduce(function (a, sample) { return a + sample.load; }, 0);
        root.movingAverage = totalLoad / recentLoads.length;
        root.evaluate();
    }

    function evaluate() {
        var now = Date.now();

        var rawHigh = root.movingAverage > root.highLoadThreshold;
        if (rawHigh !== root.highSide) { root.highSide = rawHigh; root.highSideSince = now; }
        if (now - root.highSideSince >= root.highSustainMs) root.highDebounced = rawHigh;

        var rawLow = root.movingAverage < root.lowLoadThreshold;
        if (rawLow !== root.lowSide) { root.lowSide = rawLow; root.lowSideSince = now; }
        if (now - root.lowSideSince >= root.lowSustainMs) root.lowDebounced = rawLow;

        var recommended = PowerProfile.Balanced;
        if (root.highDebounced) recommended = PowerProfile.Performance;
        else if (UPower.onBattery && root.lowDebounced) recommended = PowerProfile.PowerSaver;

        if (recommended !== root.appliedProfile && now - root.lastSwitchTime >= root.switchCooldownMs) {
            root.appliedProfile = recommended;
            root.lastSwitchTime = now;
        }
    }
}
