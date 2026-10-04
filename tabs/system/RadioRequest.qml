import QtQuick
import qs.services

/**
 * One list's request for a shared radio job (see RadioRequests.qml). Set
 * `wanted` to true while the list is visible and needs the job. The request
 * moves with `device` and is released when the list is destroyed.
 */
QtObject {
    id: root

    /** "discovery" for a Bluetooth adapter, "scan" for a Wi-Fi device. */
    property string kind: "discovery"

    /** The adapter or Wi-Fi device, or null. */
    property var device: null

    property bool wanted: false

    /** The device this request counts now, or null. */
    property var held: null

    function sync() {
        var target = root.wanted ? root.device : null;
        if (target === root.held) return;
        if (root.held) RadioRequests.release(root.kind, root.held);
        root.held = target;
        if (root.held) RadioRequests.acquire(root.kind, root.held);
    }

    onDeviceChanged: sync()
    onWantedChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: {
        if (root.held) RadioRequests.release(root.kind, root.held);
    }
}
