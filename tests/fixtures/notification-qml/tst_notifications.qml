import QtQuick
import QtTest
import Quickshell.Services.Notifications
import qs.notifications
import "qs/pill"
import "qs/tabs/alerts"

TestCase {
    id: testCase
    name: "NotificationBounds"
    when: windowShown
    width: 1000
    height: 700

    QtObject {
        id: pill
        property bool panelOpen: false
        property real dpr: 1
        property real maskWidth: 124
        property real width: 124
        property real x: 0
        property real y: 0
        property real pillHeight: 34
        property var tabIds: ["alerts"]
        property int activeTab: 0
        function openPanel() { panelOpen = true; }
    }
    PillPopup { id: popup; pill: pill; screenName: "test" }
    AlertsTab { id: alerts; width: 1000; height: 700; visible: false }

    // Replaces a sender object at the D-Bus boundary, including its change signals.
    function notification(values) {
        var n = Object.assign({
            id: 0, tracked: false, lastGeneration: false, appName: "Test", appIcon: "",
            desktopEntry: "", image: "", summary: "Before", body: "",
            urgency: NotificationUrgency.Critical, actions: [], transient: false,
            resident: false, expireTimeout: 0, dismissCount: 0
        }, values);
        var names = ["closed", "summaryChanged", "bodyChanged", "appIconChanged", "urgencyChanged",
            "actionsChanged", "appNameChanged", "desktopEntryChanged", "imageChanged",
            "transientChanged", "expireTimeoutChanged"];
        names.forEach(function (name) {
            var listeners = [];
            n[name] = {
                connect: function (f) { listeners.push(f); },
                disconnect: function (f) { listeners = listeners.filter(function (x) { return x !== f; }); },
                emit: function (value) { listeners.slice().forEach(function (f) { f(value); }); }
            };
        });
        n.dismiss = function () { n.dismissCount++; n.closed.emit(NotificationCloseReason.Dismissed); };
        n.expire = function () { n.closed.emit(NotificationCloseReason.Expired); };
        return n;
    }

    // The saved-state replacement is a direct child of the real store.
    function savedState() {
        for (var i = 0; i < Notifications.children.length; i++)
            if (Notifications.children[i].name === "notifications") return Notifications.children[i];
        fail("Saved-state boundary not found");
    }

    function init() {
        popup.hideNow();
        Notifications.all = [];
        Notifications.live = Object.create(null);
        Notifications.liveIdByServerId = Object.create(null);
        Notifications.expiresAtById = Object.create(null);
        Notifications.dnd = false;
        Notifications.refresh();
        savedState().saveCount = 0;
    }

    function test_criticalTraffic() {
        var body = "x".repeat(100 * 1024);
        for (var i = 0; i < 1000; i++) {
            var n = notification({ id: i, body: body });
            Notifications.receive(n);
        }
        compare(Object.keys(Notifications.live).length, 200);
        compare(popup.queue.length, 20);
        compare(Notifications.all.length, 200);
    }
}
