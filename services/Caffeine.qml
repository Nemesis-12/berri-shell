pragma Singleton
import QtQuick
import Quickshell

/**
 * Caffeine: keeps the screen awake. The state lives for this session only,
 * as there is nothing to read back on start. The one invisible window that
 * holds the idle inhibitor is in shell.qml and follows `on`. Every view
 * (one per monitor) reads and toggles this one value.
 */
Singleton {
    id: root

    property bool on: false

    function toggle() {
        root.on = !root.on;
    }
}
