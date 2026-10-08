pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * Saves and restores the chosen power mode ("saver"/"balanced"/"performance"
 * /"auto") separately for AC and battery power, in
 * ~/.local/state/berri-shell/power-modes.json. Applies the saved mode for
 * the current power source on start and on every plug/unplug. A manual mode
 * sets PowerProfiles.profile directly; "auto" follows AutoPowerProfile's
 * live decisions instead.
 */
Singleton {
    id: root

    readonly property string defaultMode: "auto"

    property string acMode: defaultMode
    property string batteryMode: defaultMode

    /** The saved mode for whichever power source is active right now. */
    readonly property string activeMode: UPower.onBattery ? batteryMode : acMode

    /** Called by the mode buttons; saves the choice and applies it at once. */
    function setMode(mode) {
        if (UPower.onBattery) root.batteryMode = mode;
        else root.acMode = mode;
        root.save();
        root.apply();
    }

    function profileForMode(mode) {
        if (mode === "saver") return PowerProfile.PowerSaver;
        if (mode === "performance") return PowerProfile.Performance;
        if (mode === "auto") return AutoPowerProfile.profile;
        return PowerProfile.Balanced;
    }

    /**
     * Pushes the profile for the current source's saved mode to PowerProfiles.
     * Skips Performance until hasPerformanceProfile is true: on startup
     * PowerProfiles has not finished loading the device's profile list yet,
     * and setting Performance before then is rejected with an error even on
     * laptops that do have it. The hasPerformanceProfileChanged handler below
     * re-applies once it becomes true.
     */
    function apply() {
        var wanted = root.profileForMode(root.activeMode);
        if (wanted === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) return;
        if (PowerProfiles.profile !== wanted) PowerProfiles.profile = wanted;
    }

    function save() {
        saved.save({ ac: root.acMode, battery: root.batteryMode });
    }

    SavedState {
        id: saved
        name: "power-modes"
        defaults: ({ ac: root.defaultMode, battery: root.defaultMode })
        onLoaded: values => {
            if (values.ac) root.acMode = values.ac;
            if (values.battery) root.batteryMode = values.battery;
            root.apply();
        }
    }

    // Re-applies whenever the source changes (activeMode picks up onBattery)
    // or auto mode's own recommendation changes while it is the active mode.
    onActiveModeChanged: root.apply()
    Connections {
        target: AutoPowerProfile
        function onProfileChanged() {
            if (root.activeMode === "auto") root.apply();
        }
    }

    // PowerProfiles.profile only reflects its real DBus value once the
    // property finishes its first async fetch (it reads Balanced, its
    // default, until then), so the very first apply() above can compare
    // against a value that has not arrived yet. Re-checking on every change
    // also catches that first real update and corrects it if needed.
    Connections {
        target: PowerProfiles
        function onProfileChanged() { root.apply(); }
        function onHasPerformanceProfileChanged() { root.apply(); }
    }
}
