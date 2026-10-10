pragma Singleton
import QtQuick
import Quickshell

/**
 * Pairing of Bluetooth devices. A device list asks to pair a device. When
 * BlueZ finishes pairing, this service trusts and connects the device, even
 * if the list is closed by then. Each device is tracked on its own. A pairing
 * that ends without success is forgotten, so a later pairing of that device
 * does not connect by surprise.
 */
Singleton {
    id: root

    /** Devices that are being paired now. */
    property var pending: []

    /** Starts pairing `device`. Trust and connect follow when pairing succeeds. */
    function pair(device) {
        if (root.pending.indexOf(device) < 0) root.pending = root.pending.concat([device]);
        device.pair();
    }

    function forget(device) {
        root.pending = root.pending.filter(function (item) { return item !== device; });
    }

    // Pairing may end before the paired state arrives, so the state is read once the signals settle.
    function checkEnded(device) {
        Qt.callLater(function () {
            if (!device.pairing && !device.paired) root.forget(device);
        });
    }

    function finish(device) {
        root.forget(device);
        device.trusted = true;
        device.connect();
    }

    Instantiator {
        model: root.pending

        delegate: Connections {
            required property var modelData
            target: modelData

            function onPairedChanged() {
                if (modelData.paired) root.finish(modelData);
            }

            function onPairingChanged() {
                if (!modelData.pairing) root.checkEnded(modelData);
            }
        }
    }
}
