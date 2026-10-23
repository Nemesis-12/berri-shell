pragma Singleton
import QtQuick
import Quickshell

/**
 * Pairing and forgetting of Bluetooth devices. A device list asks to pair or
 * forget a device. When BlueZ finishes pairing, this service trusts and
 * connects the device, even if the list is closed by then. If the device is
 * still connected for the pairing link only, it connects when that link
 * drops. Each device is tracked on its own. A device leaves the list when it is paired, when its
 * pair call fails, or when it is destroyed. The paired state may arrive after pairing ends, so it is
 * still watched for a short time (`graceMs`) after that. After this time a
 * device that is not paired is dropped, so a later pairing from another
 * tool does not trust and connect it by surprise.
 */
Singleton {
    id: root

    /** Devices that are being paired now. */
    property var pending: []

    // BlueZ can set `paired` in a later event-loop turn than `pairing`. 2 s is
    // long enough for that, and short enough that a later pairing is not ours.
    readonly property int graceMs: 2000

    // While BlueZ pairs, the device is `connected` for the pairing link only. Quickshell
    // ignores connect() on a connected device, and the link may drop right after pairing.
    // So a device that is connected when pairing ends is followed for `followMs`, and
    // connected once when it drops. Tests may shorten this time.
    property int followMs: 10000

    // Paired devices that are connected for the pairing link only.
    property var following: []

    // Devices whose pairing ended without success: { device, at } with the drop time.
    property var ending: []

    /** Starts pairing `device`. Trust and connect follow when pairing succeeds. */
    function pair(device) {
        root.unwatch(device);
        root.pending = root.pending.concat([device]);
        try {
            device.pair();
        } catch (error) {
            root.unwatch(device);
        }
    }

    /**
     * Stops following the pairing of `device`. Also drops destroyed devices.
     * A destroyed device sends no signal, so they leave at the next call.
     */
    function unwatch(device) {
        root.pending = root.pending.filter(function (item) { return Qt.isQtObject(item) && item !== device; });
        root.ending = root.ending.filter(function (item) { return Qt.isQtObject(item.device) && item.device !== device; });
        root.following = root.following.filter(function (item) { return Qt.isQtObject(item) && item !== device; });
    }

    /**
     * Forgets `device`: BlueZ removes it from the adapter and, if it is
     * connected, disconnects it first. A pairing that still runs is cancelled.
     * A device that is found again is a new object, so nothing of this one
     * stays. Does nothing for a device that is already destroyed.
     */
    function forget(device) {
        if (!Qt.isQtObject(device)) return;
        root.unwatch(device);
        if (device.pairing) {
            try {
                device.cancelPair();
            } catch (error) {
                // The forget below still removes the device.
            }
        }
        device.forget();
    }

    // Pairing ended and the device is not paired: keep it for `graceMs`, then drop it.
    function pairingEnded(device) {
        root.ending = root.ending.filter(function (item) { return item.device !== device; })
            .concat([{ device: device, at: Date.now() + root.graceMs }]);
        root.scheduleDrop();
    }

    // Sets the drop timer for the earliest deadline in `ending`.
    function scheduleDrop() {
        if (root.ending.length === 0) {
            dropTimer.stop();
            return;
        }
        const next = Math.min.apply(null, root.ending.map(function (item) { return item.at; }));
        dropTimer.interval = Math.max(1, next - Date.now());
        dropTimer.restart();
    }

    // Trusts and connects a paired device, unless its grace period is over.
    // A device that is connected now is connected later, when its link drops.
    function finish(device) {
        const waiting = root.ending.find(function (item) { return item.device === device; });
        if (waiting && waiting.at <= Date.now()) {
            root.unwatch(device);
            return;
        }
        root.unwatch(device);
        device.trusted = true;
        if (device.connected) {
            root.following = root.following.concat([device]);
        } else {
            device.connect();
        }
    }

    // The pairing link of `device` dropped: connect it for real.
    function linkDropped(device) {
        root.unwatch(device);
        device.connect();
    }

    // Runs only while a device waits in `ending`.
    Timer {
        id: dropTimer
        onTriggered: {
            const now = Date.now() + 20;
            const late = root.ending.filter(function (item) { return item.at <= now; });
            late.forEach(function (item) { root.unwatch(item.device); });
            root.scheduleDrop();
        }
    }

    Instantiator {
        model: root.pending

        delegate: Connections {
            required property var modelData
            target: modelData

            function onPairingChanged() {
                if (!modelData.pairing && !modelData.paired) root.pairingEnded(modelData);
            }

            function onPairedChanged() {
                if (modelData.paired) root.finish(modelData);
            }
        }
    }

    // One delegate per followed device: it connects on a drop and gives up after `followMs`.
    Instantiator {
        model: root.following

        delegate: Scope {
            required property var modelData

            Connections {
                target: modelData

                function onConnectedChanged() {
                    if (!modelData.connected) root.linkDropped(modelData);
                }
            }

            Timer {
                interval: root.followMs
                running: true
                onTriggered: root.unwatch(modelData)
            }
        }
    }
}
