import QtQuick
import Quickshell
import qs.notifications

// Loads only the notification service on the test's private bus and home.
Scope {
    readonly property var service: Notifications

    Connections {
        target: Notifications
        // Notifications refreshes its lists in a queued call. Wait one turn.
        function onArrived(item) {
            Qt.callLater(function () {
                console.log("notification-after-receive " + JSON.stringify({
                    dnd: Notifications.dnd, items: Notifications.items
                }));
            });
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: console.log("notification-state " + JSON.stringify({
            dnd: Notifications.dnd, items: Notifications.items
        }))
    }
}
