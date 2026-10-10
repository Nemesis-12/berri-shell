pragma Singleton
import QtQuick
import Quickshell

/**
 * Pairing of Bluetooth devices. A device list asks to pair a device. When
 * BlueZ finishes pairing, this service trusts and connects the device, even
 * if the list is closed by then. Each device is tracked on its own. A device
 * leaves the list when it is paired, when its pair call fails, or when it is
 * destroyed. The paired state may arrive after pairing ends, so it is
 * still watched until then.
 */
Singleton {
    id: root

    /** Devices that are being paired now. */
    property var pending: []

    /** Starts pairing `device`. Trust and connect follow when pairing succeeds. */
    function pair(device) {
        root.forget(device);
        root.pending = root.pending.concat([device]);
        try {
            device.pair();
        } catch (error) {
            root.forget(device);
        }
    }

    // Also drops destroyed devices. A destroyed device sends no signal, so they leave at the next call.
    function forget(device) {
        root.pending = root.pending.filter(function (item) { return Qt.isQtObject(item) && item !== device; });
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
        }
    }
}
