pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * Sends one critical notification each time the battery falls to the
 * threshold while discharging. The notification is transient: it shows as
 * a pop-up and is not kept in the history. No alert is sent until the
 * device is ready and gives a real reading (percentage above 0), so a
 * shell reload never sends a false alert. Re-arms when the battery charges or rises
 * above the threshold. This is a singleton so only one alert runs, no
 * matter how many monitors show a Battery cell. shell.qml keeps it active.
 */
Singleton {
    id: root

    readonly property int threshold: 10

    readonly property var device: UPower.displayDevice
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool discharging: device ? device.state === UPowerDeviceState.Discharging : false

    /** True after the alert was sent, until the battery charges or rises above the threshold. */
    property bool notified: false

    onPercentChanged: check()
    onDischargingChanged: check()
    Connections {
        target: root.device
        function onReadyChanged() { root.check(); }
        function onIsPresentChanged() { root.check(); }
    }
    Component.onCompleted: check()

    function check() {
        if (!device || !device.ready || !device.isPresent || percent <= 0) return;
        if (!discharging || percent > threshold) {
            notified = false;
            return;
        }
        if (notified) return;
        notified = true;
        notifyProc.command = ["notify-send", "-u", "critical", "-h", "boolean:transient:true",
            "Battery at " + percent + "%", "Plug in the charger."];
        notifyProc.running = true;
    }

    Process {
        id: notifyProc
    }
}
