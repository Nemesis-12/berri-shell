pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import "../logic/AirplaneLogic.js" as AirplaneLogic
import qs.common

/**
 * Airplane mode (ticket 18): turns Wi-Fi and Bluetooth off and remembers
 * their prior on/off state; turning it off restores them. Turning either
 * radio on again - from its tile, its list's switch, or outside the shell -
 * clears airplane mode, same as the mock. The decision logic itself lives in
 * AirplaneLogic.js so it can run outside Quickshell for testing.
 *
 * State is saved with SavedState in ~/.local/state/berri-shell/airplane.json
 * so a shell restart keeps it. On start, if the saved state says airplane is on but a radio is already on, airplane is
 * cleared instead of turning that radio back off.
 */
Singleton {
    id: root

    property bool on: false
    property bool memoValid: false
    property bool memoWifi: false
    property bool memoBt: false

    readonly property var btAdapter: Bluetooth.defaultAdapter

    /** Flips airplane mode, applying the same remember/restore/clear logic
     *  as the mock's toggle('air'). */
    function toggle() {
        var next = AirplaneLogic.nextState({
            air: root.on, memoValid: root.memoValid,
            memoWifi: root.memoWifi, memoBt: root.memoBt,
            wifi: Networking.wifiEnabled,
            bt: root.btAdapter ? root.btAdapter.enabled : false
        }, "toggleAir");

        root.on = next.air;
        root.memoValid = next.memoValid;
        root.memoWifi = next.memoWifi;
        root.memoBt = next.memoBt;
        Networking.wifiEnabled = next.wifi;
        if (root.btAdapter) root.btAdapter.enabled = next.bt;
        root.save();
    }

    /** Called whenever Wi-Fi or Bluetooth turns on for any reason; clears
     *  airplane mode if it was set. No-op otherwise. */
    function radioTurnedOn() {
        if (!root.on) return;
        var next = AirplaneLogic.nextState({ air: root.on, memoValid: root.memoValid }, "radioOn");
        root.on = next.air;
        root.memoValid = next.memoValid;
        root.memoWifi = next.memoWifi;
        root.memoBt = next.memoBt;
        root.save();
    }

    /** Runs once at startup: a radio that is already on when the saved state
     *  says airplane is on means the saved state is stale (or a radio was
     *  turned on before this check ran) - clear airplane rather than turn
     *  that radio back off. */
    function checkStartupConsistency() {
        if (!root.on) return;
        var wifiOn = Networking.wifiEnabled;
        var btOn = root.btAdapter ? root.btAdapter.enabled : false;
        if (wifiOn || btOn) {
            root.on = false;
            root.memoValid = false;
            root.memoWifi = false;
            root.memoBt = false;
            root.save();
        }
    }

    function save() {
        saved.save({
            on: root.on, memoValid: root.memoValid,
            memoWifi: root.memoWifi, memoBt: root.memoBt
        });
    }

    SavedState {
        id: saved
        name: "airplane"
        defaults: ({ on: false, memoValid: false, memoWifi: false, memoBt: false })
        onLoaded: values => {
            root.on = !!values.on;
            root.memoValid = !!values.memoValid;
            root.memoWifi = !!values.memoWifi;
            root.memoBt = !!values.memoBt;
            startupCheck.running = true;
        }
    }

    // Wi-Fi and Bluetooth may not be resolved yet right when the file loads,
    // so the consistency check runs a moment later instead of inline.
    Timer {
        id: startupCheck
        interval: 600
        repeat: false
        onTriggered: root.checkStartupConsistency()
    }

    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (Networking.wifiEnabled) root.radioTurnedOn();
        }
    }

    Connections {
        target: root.btAdapter
        enabled: root.btAdapter !== null
        function onEnabledChanged() {
            if (root.btAdapter.enabled) root.radioTurnedOn();
        }
    }
}
