pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Night light: hyprsunset, driven through its hyprctl IPC, matching
 * omarchy-toggle-nightlight (/usr/share/omarchy/bin/omarchy-toggle-nightlight):
 * state comes from the reported temperature (below 6000 = on), turning on
 * sets 4000K and turning off sets 6500K - never "identity", which resets
 * the screen but leaves the query reporting the old temperature, so the
 * tile would read ON while the screen is back to normal. A freshly
 * started hyprsunset applies its own default at the end of its boot,
 * overriding an early command, so the set is resent until it sticks.
 *
 * A request that comes while a write runs is kept. Only the latest one
 * is written when that write ends.
 *
 * Another program can change the temperature, so the state is read again
 * every 5 s, but only while a view is visible (`viewers` > 0) and once
 * when a view opens.
 */
Singleton {
    id: root

    readonly property int onTemperature: 4000
    readonly property int offTemperature: 6500

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    property bool on: false

    /** Latest requested temperature that no write has started for yet; 0 means none. */
    property int waitingTemperature: 0

    /** The state the user asked for last, also while a write still runs. */
    readonly property bool wantedOn: {
        if (root.waitingTemperature !== 0) return root.waitingTemperature < 6000;
        if (temperatureSetter.running) return temperatureSetter.targetTemperature < 6000;
        return root.on;
    }

    /** Saves the request. It is written now, or when the running write ends. */
    function setOn(wanted: bool): void {
        root.waitingTemperature = wanted ? root.onTemperature : root.offTemperature;
        root.startWaitingWrite();
    }

    function startWaitingWrite(): void {
        if (temperatureSetter.running || root.waitingTemperature === 0) return;
        temperatureSetter.targetTemperature = root.waitingTemperature;
        root.waitingTemperature = 0;
        temperatureSetter.running = true;
    }

    function toggle() {
        root.setOn(!root.wantedOn);
    }

    onViewersChanged: if (viewers === 1) temperatureReader.running = true

    Process {
        id: temperatureReader
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var temperature = parseInt(text.trim(), 10);
                root.on = !isNaN(temperature) && temperature < 6000;
            }
        }
        onExited: (code) => { if (code !== 0) root.on = false; }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.viewers > 0
        onTriggered: temperatureReader.running = true
    }

    Process {
        id: temperatureSetter
        property int targetTemperature: 0
        command: ["bash", "-c",
            "pgrep -x hyprsunset >/dev/null || (setsid hyprsunset >/dev/null 2>&1 &); " +
            "for i in 1 2 3 4 5 6 7 8 9 10; do " +
            "  hyprctl hyprsunset temperature " + targetTemperature + " >/dev/null 2>&1; " +
            "  sleep 0.2; " +
            "  [ \"$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1)\" = \"" + targetTemperature + "\" ] && break; " +
            "done"]
        onExited: {
            if (root.waitingTemperature !== 0) root.startWaitingWrite();
            else temperatureReader.running = true;
        }
    }
}
