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
    visible: true
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
    SignalSpy { id: historyChanges; target: Notifications; signalName: "allChanged" }

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
        Notifications.flush();
        Notifications.writeSaved();
        popup.hideNow();
        alerts.visible = false;
        alerts.filter = "all";
        Notifications.all = [];
        Notifications.live = Object.create(null);
        Notifications.liveIdByServerId = Object.create(null);
        Notifications.expiresAtById = Object.create(null);
        Notifications.dnd = false;
        Notifications.refresh();
        savedState().saveCount = 0;
    }

    function test_criticalTraffic() {
        for (var i = 0; i < 1000; i++) {
            var n = notification({ id: i, body: "x".repeat(100 * 1024 - 6) + ("000000" + i).slice(-6) });
            Notifications.receive(n);
            verify(Object.keys(Notifications.live).length <= 200, "Live senders exceed 200");
        }
        compare(Object.keys(Notifications.live).length, 200);
        compare(popup.queue.length, 20);
        compare(Notifications.all.length, 200);
        compare(Notifications.all[0].body.length, 4096);
        tryCompare(savedState(), "saveCount", 1, 1000);
        verify(savedState().text.length < 1024 * 1024, "ASCII history exceeds 1 MiB");
        console.log("History JSON characters after 1000 critical items:", savedState().text.length);
    }

    function test_transientTrafficAndLateSignals() {
        var first = notification({ id: 0, transient: true, body: "x".repeat(100 * 1024) });
        Notifications.receive(first);
        for (var i = 1; i < 1000; i++)
            Notifications.receive(notification({ id: i, transient: true, body: "x".repeat(100 * 1024) }));
        compare(Object.keys(Notifications.live).length, 200);
        compare(Object.keys(Notifications.liveIdByServerId).length, 200);
        compare(popup.queue.length, 20);
        compare(Notifications.all.length, 0);
        compare(first.dismissCount, 1);
        first.summaryChanged.emit();
        compare(Object.keys(Notifications.live).length, 200);
        compare(Notifications.liveIdByServerId[0], undefined);
        compare(popup.current.body.length, 4096);
        compare(savedState().saveCount, 0);
    }

    function test_transientUpdateDropsHistoryOnly() {
        var n = notification({ id: 1 });
        Notifications.receive(n);
        n.transient = true;
        n.transientChanged.emit();
        compare(Notifications.all.length, 0);
        compare(popup.current.id, Notifications.liveIdByServerId[1]);
        verify(popup.open);
        compare(n.dismissCount, 0);
    }

    function test_transientExpiryEntriesShareLiveLimit() {
        var n;
        for (var i = 0; i <= 200; i++) {
            n = notification({ id: i, transient: true, urgency: NotificationUrgency.Normal, expireTimeout: 3600 });
            Notifications.receive(n);
        }
        compare(Object.keys(Notifications.live).length, 200);
        compare(Object.keys(Notifications.expiresAtById).length, 200);
        compare(popup.queue.length, 20);
        n.expireTimeout = 0.001;
        n.expireTimeoutChanged.emit();
        tryVerify(function () { return Notifications.liveIdByServerId[200] === undefined; }, 1000);
        compare(Object.keys(Notifications.live).length, 199);
        compare(Object.keys(Notifications.expiresAtById).length, 199);
        compare(Notifications.all.length, 0);
    }

    function test_updateCost() {
        for (var i = 0; i < 199; i++) Notifications.receive(notification({ id: i }));
        var n = notification({ id: 200 });
        Notifications.receive(n);
        wait(0);
        var samples = [];
        for (var sample = 0; sample < 9; sample++) {
            savedState().saveCount = 0;
            var start = Date.now();
            for (var j = 0; j < 10; j++) {
                n.summary = "Update " + j;
                n.summaryChanged.emit();
            }
            Notifications.flush();
            samples.push(Date.now() - start);
            tryCompare(savedState(), "saveCount", 1, 1000);
            compare(Notifications.items.filter(function (item) { return item.serverId === 200; })[0].summary, "Update 9");
            compare(JSON.parse(savedState().text).items[199].summary, "Update 9");
        }
        samples.sort(function (a, b) { return a - b; });
        console.log("Ten updates with 200 stored items, including flush, median:", samples[4], "ms; samples:", samples);
        verify(samples[4] < 3, "Ten updates took a median of " + samples[4] + " ms");
    }

    // Reads the real text bindings in a pop-up, without pointer or keyboard input.
    function hasText(item, text) {
        if (item.text === text) return true;
        for (var i = 0; i < item.children.length; i++)
            if (hasText(item.children[i], text)) return true;
        return false;
    }

    function test_currentAndQueuedUpdates() {
        var n = notification({ id: 1, actions: [{ identifier: "old", text: "Old action" }] });
        Notifications.receive(n);
        verify(hasText(popup, "Before"));
        n.summary = "After";
        n.actions = [{ identifier: "new", text: "New action" }];
        n.summaryChanged.emit();
        n.actionsChanged.emit();
        compare(popup.current.summary, "After");
        verify(hasText(popup, "After"));
        verify(hasText(popup, "New action"));
        compare(popup.current.actions[0].id, "new");
        compare(popup.queue.length, 0);
        Notifications.receive(notification({ id: 2, summary: "Other" }));
        compare(popup.queue.length, 1);
        n.summary = "Queued update";
        n.summaryChanged.emit();
        compare(popup.current.summary, "Other");
        compare(popup.queue.length, 1);
        compare(popup.queue[0].summary, "Queued update");
        popup.close();
        popup.showNext();
        compare(popup.current.summary, "Queued update");
    }

    function test_updatedActionsInvokeCurrentSenderOnly() {
        var oldCalls = 0, newCalls = 0;
        var n = notification({ id: 1, resident: true,
            actions: [{ identifier: "old", text: "Old", invoke: function () { oldCalls++; } }] });
        Notifications.receive(n);
        n.actions = [{ identifier: "new", text: "New", invoke: function () { newCalls++; } }];
        n.actionsChanged.emit();
        Notifications.invokeAction(popup.current.id, popup.current.actions[0].id);
        compare(oldCalls, 0);
        compare(newCalls, 1);
        compare(Notifications.all[0].read, true);
        compare(n.dismissCount, 0);
    }

    function test_actionTextAndCountAreBounded() {
        var actions = [];
        for (var i = 0; i < 30; i++) actions.push({ identifier: "action" + i, text: "x".repeat(100 * 1024) });
        actions[0].identifier = "x".repeat(129);
        Notifications.receive(notification({ id: 1, actions: actions }));
        compare(popup.current.actions.length, 15);
        compare(popup.current.actions[0].id, "action1");
        compare(popup.current.actions[0].label.length, 256);
        compare(popup.current.actions[14].id, "action15");
    }

    // Finds a real Alerts row so its snooze signal exercises the UI connection.
    function alertRow(item, title) {
        if (item.title === title && item.snooze) return item;
        for (var i = 0; i < item.children.length; i++) {
            var row = alertRow(item.children[i], title);
            if (row) return row;
        }
        return null;
    }

    function test_snoozeUsesSharedDuration() {
        Notifications.receive(notification({ id: 1, summary: "Wake later" }));
        Notifications.flush();
        alerts.visible = true;
        alerts.rebuild();
        wait(50);
        var row = alertRow(alerts, "Wake later");
        verify(row !== null, "Alerts row not found");
        var start = Date.now();
        row.snooze();
        var end = Date.now();
        var wake = Notifications.all[0].snoozedUntil;
        verify(wake >= start + Notifications.defaultSnoozeMinutes * 60000);
        verify(wake <= end + Notifications.defaultSnoozeMinutes * 60000);
        Notifications.flush();
        compare(Notifications.items.length, 0);
        compare(Notifications.snoozedCount, 1);
    }

    // Reads the models used by the real Alerts ListViews.
    function viewModels(item) {
        var found = [];
        if (item.model && item.model.get) found.push(item.model);
        for (var i = 0; i < item.children.length; i++) found = found.concat(viewModels(item.children[i]));
        return found;
    }

    function test_senderNames() {
        var names = ["constructor", "toString", "__proto__"];
        for (var i = 0; i < names.length; i++) Notifications.receive(notification({ id: i, appName: names[i] }));
        wait(0);
        alerts.visible = true;
        alerts.rebuild();
        var models = viewModels(alerts);
        var rows = models.filter(function (m) { return m.count > 0 && m.get(0).kind === "header"; })[0];
        verify(rows !== undefined, "Alerts list has no headers");
        compare(rows.count, 6);
        names.forEach(function (name) {
            var headers = 0, notes = 0;
            for (var j = 0; j < rows.count; j++) {
                if (rows.get(j).appName !== name) continue;
                if (rows.get(j).kind === "header") headers++;
                if (rows.get(j).kind === "row") notes++;
            }
            compare(headers, 1);
            compare(notes, 1);
        });
        verify(alerts.visible);
    }

    function test_senderNamedAllCanBeFiltered() {
        Notifications.receive(notification({ id: 1, appName: "all" }));
        Notifications.receive(notification({ id: 2, appName: "Other" }));
        wait(0);
        alerts.filter = "app:all";
        alerts.rebuild();
        compare(alerts.shown.length, 1);
        compare(alerts.shown[0].appName, "all");
        alerts.readShown();
        compare(Notifications.all.filter(function (n) { return n.read; }).length, 1);
        compare(Notifications.all.filter(function (n) { return n.read; })[0].appName, "all");
    }

    function test_readAndClearBatch() {
        for (var i = 0; i < 200; i++) Notifications.receive(notification({ id: i }));
        wait(0);
        alerts.rebuild();
        savedState().saveCount = 0;
        historyChanges.clear();
        alerts.readShown();
        compare(Notifications.all.filter(function (n) { return !n.read; }).length, 0);
        compare(historyChanges.count, 1);
        tryCompare(savedState(), "saveCount", 1, 1000);
        compare(JSON.parse(savedState().text).items.filter(function (n) { return !n.read; }).length, 0);
        savedState().saveCount = 0;
        historyChanges.clear();
        alerts.clearShown();
        compare(Notifications.all.length, 0);
        compare(Object.keys(Notifications.live).length, 0);
        compare(historyChanges.count, 1);
        tryCompare(savedState(), "saveCount", 1, 1000);
        compare(JSON.parse(savedState().text).items.length, 0);
    }
}
