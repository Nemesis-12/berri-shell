pragma Singleton
import QtQuick
import Quickshell
import "../logic/RequestCounts.js" as Counts

/**
 * Shared radio requests. Two monitors can show a Wi-Fi or Bluetooth list at
 * the same time, and both use the same device. Each list asks through a
 * RadioRequest. The device stays on while at least one list asks, and goes
 * off when the last list lets go.
 *
 * kind "discovery": a Bluetooth adapter looks for devices (`discovering`).
 * kind "scan": a Wi-Fi device scans for networks (`scannerEnabled`).
 */
Singleton {
    id: root

    property var tables: ({ discovery: Counts.create(), scan: Counts.create() })

    /** One more list asks for `kind` on `device`. */
    function acquire(kind, device) {
        root.apply(kind, device, Counts.acquire(root.tables[kind], device));
    }

    /** One list lets go. The device goes off when no list is left. */
    function release(kind, device) {
        root.apply(kind, device, Counts.release(root.tables[kind], device));
    }

    function apply(kind, device, count) {
        var on = count > 0;
        if (kind === "discovery") {
            if (device.discovering !== on) device.discovering = on;
        } else if (device.scannerEnabled !== on) {
            device.scannerEnabled = on;
        }
    }
}
