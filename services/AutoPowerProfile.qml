pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../logic/PowerProfileLogic.js" as Rules

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
        var recentLoads = Rules.recentSamples(root.loadSamples, { time: Date.now(), load: load }, root.averageWindowMs);
        root.loadSamples = recentLoads;
        root.movingAverage = Rules.averageLoad(recentLoads);
        root.evaluate();
    }

    function profileFor(name) {
        if (name === "performance") return PowerProfile.Performance;
        if (name === "power-saver") return PowerProfile.PowerSaver;
        return PowerProfile.Balanced;
    }

    function evaluate() {
        var now = Date.now();

        var high = Rules.sustainedSide({ side: root.highSide, since: root.highSideSince, debounced: root.highDebounced },
            root.movingAverage > root.highLoadThreshold, now, root.highSustainMs);
        root.highSide = high.side; root.highSideSince = high.since; root.highDebounced = high.debounced;

        var low = Rules.sustainedSide({ side: root.lowSide, since: root.lowSideSince, debounced: root.lowDebounced },
            root.movingAverage < root.lowLoadThreshold, now, root.lowSustainMs);
        root.lowSide = low.side; root.lowSideSince = low.since; root.lowDebounced = low.debounced;

        var recommended = root.profileFor(Rules.recommendedProfile(root.highDebounced, root.lowDebounced, UPower.onBattery));
        if (Rules.mayAdopt(recommended, root.appliedProfile, now, root.lastSwitchTime, root.switchCooldownMs)) {
            root.appliedProfile = recommended;
            root.lastSwitchTime = now;
        }
    }
}
