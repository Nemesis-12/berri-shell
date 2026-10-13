import QtQuick
import QtTest
import Quickshell.Services.Notifications
import qs.notifications
import "qs/tabs/alerts"

TestCase {
    id: testCase
    name: "NotificationBounds"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    NotificationPopup {
        id: popup
        anchorRect: Qt.rect(0, 0, 124, 34)
        dpr: 1
        dashboardOpen: false
        screenName: "test"
    }
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
        popup._hideNow();
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
        compare(popup._queue.length, 20);
        compare(Notifications.all.length, 200);
        compare(Notifications.all[0].body.length, 4096);
        tryCompare(savedState(), "saveCount", 1, 10000);
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
        compare(popup._queue.length, 20);
        compare(Notifications.all.length, 0);
        compare(first.dismissCount, 1);
        first.summaryChanged.emit();
        compare(Object.keys(Notifications.live).length, 200);
        compare(Notifications.liveIdByServerId[0], undefined);
        compare(popup._current.body.length, 4096);
        compare(savedState().saveCount, 0);
    }

    function test_transientUpdateDropsHistoryOnly() {
        var n = notification({ id: 1 });
        Notifications.receive(n);
        n.transient = true;
        n.transientChanged.emit();
        compare(Notifications.all.length, 0);
        compare(popup._current.id, Notifications.liveIdByServerId[1]);
        verify(popup._open);
        compare(n.dismissCount, 0);
    }

    function test_transientExpiryEntriesShareLiveLimit() {
        var n;
        for (var i = 0; i <= 200; i++) {
            n = notification({ id: i, transient: true, urgency: NotificationUrgency.Normal, expireTimeout: 3600000 });
            Notifications.receive(n);
        }
        compare(Object.keys(Notifications.live).length, 200);
        compare(Object.keys(Notifications.expiresAtById).length, 200);
        compare(popup._queue.length, 20);
        n.expireTimeout = 1;
        n.expireTimeoutChanged.emit();
        tryVerify(function () { return Notifications.liveIdByServerId[200] === undefined; }, 10000);
        compare(Object.keys(Notifications.live).length, 199);
        compare(Object.keys(Notifications.expiresAtById).length, 199);
        compare(Notifications.all.length, 0);
    }

    // The sender timeout is in milliseconds (freedesktop spec), as Quickshell passes it on.
    function test_sixtySecondNotificationExpiresAfterSixtySeconds() {
        var n = notification({ id: 1, urgency: NotificationUrgency.Normal, expireTimeout: 60000 });
        var closed = [];
        n.closed.connect(function (reason) { closed.push(reason); });
        var start = Date.now();
        Notifications.receive(n);
        var id = Notifications.liveIdByServerId[1];
        var due = Notifications.expiresAtById[id];
        verify(due >= start + 60000 && due <= Date.now() + 60000, "Expiry is not 60 s ahead: " + (due - start));
        Notifications.expireDue(start + 59000);
        compare(closed.length, 0);
        verify(Notifications.live[id] === n);
        Notifications.expireDue(start + 60001);
        compare(closed, [NotificationCloseReason.Expired]);
        compare(Notifications.live[id], undefined);
    }

    function test_defaultAndNeverTimeouts() {
        Notifications.receive(notification({ id: 1, urgency: NotificationUrgency.Normal, expireTimeout: -1 }));
        var start = Date.now();
        var due = Notifications.expiresAtById[Notifications.liveIdByServerId[1]];
        verify(due >= start - 50 + 5000 && due <= start + 5000, "Default is not 5 s: " + (due - start));
        Notifications.receive(notification({ id: 2, urgency: NotificationUrgency.Normal, expireTimeout: 0 }));
        compare(Notifications.expiresAtById[Notifications.liveIdByServerId[2]], undefined);
        Notifications.receive(notification({ id: 3, expireTimeout: 60000 }));
        compare(Notifications.expiresAtById[Notifications.liveIdByServerId[3]], undefined);
    }

    // Median milliseconds for 100 updates plus one flush, with `count` stored items.
    function medianUpdateCost(count) {
        init();
        for (var i = 0; i < count - 1; i++) Notifications.receive(notification({ id: i }));
        var n = notification({ id: count });
        Notifications.receive(n);
        wait(0);
        var samples = [];
        for (var sample = 0; sample < 15; sample++) {
            savedState().saveCount = 0;
            var start = Date.now();
            for (var j = 0; j < 100; j++) {
                n.summary = "Update " + j;
                n.summaryChanged.emit();
            }
            Notifications.flush();
            samples.push(Date.now() - start);
            tryCompare(savedState(), "saveCount", 1, 10000);
            compare(Notifications.items.filter(function (item) { return item.serverId === count; })[0].summary, "Update 99");
            compare(JSON.parse(savedState().text).items[count - 1].summary, "Update 99");
        }
        samples.sort(function (a, b) { return a - b; });
        return samples[7];
    }

    // Update cost may grow with the item count, but a 4 times larger store must stay under 3.5 times the cost.
    // Each round measures both sizes back to back, so machine load affects both the same way. A burst of load
    // can still hit one size only, so the test uses the lowest ratio of 3 rounds. A real quadratic cost
    // gives a high ratio in every round.
    function test_updateCostGrowsAtMostLinearly() {
        var small = 50, large = 200;
        var lowest = Infinity;
        for (var round = 0; round < 3; round++) {
            var smallCost = Math.max(1, medianUpdateCost(small));
            var largeCost = medianUpdateCost(large);
            var ratio = largeCost / smallCost;
            console.log("Round", round, "median of 100 updates plus flush:", small, "items", smallCost, "ms;", large, "items", largeCost, "ms; ratio", ratio);
            lowest = Math.min(lowest, ratio);
        }
        verify(lowest < 3.5, "Update cost grew " + lowest + " times for " + large / small + " times more items in the best round (limit 3.5)");
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
        compare(popup._current.summary, "After");
        verify(hasText(popup, "After"));
        verify(hasText(popup, "New action"));
        compare(popup._current.actions[0].id, "new");
        compare(popup._queue.length, 0);
        Notifications.receive(notification({ id: 2, summary: "Other" }));
        compare(popup._queue.length, 1);
        n.summary = "Queued update";
        n.summaryChanged.emit();
        compare(popup._current.summary, "Other");
        compare(popup._queue.length, 1);
        compare(popup._queue[0].summary, "Queued update");
        popup._close();
        popup._showNext();
        compare(popup._current.summary, "Queued update");
    }

    function test_updatedActionsInvokeCurrentSenderOnly() {
        var oldCalls = 0, newCalls = 0;
        var n = notification({ id: 1, resident: true,
            actions: [{ identifier: "old", text: "Old", invoke: function () { oldCalls++; } }] });
        Notifications.receive(n);
        n.actions = [{ identifier: "new", text: "New", invoke: function () { newCalls++; } }];
        n.actionsChanged.emit();
        Notifications.invokeAction(popup._current.id, popup._current.actions[0].id);
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
        compare(popup._current.actions.length, 15);
        compare(popup._current.actions[0].id, "action1");
        compare(popup._current.actions[0].label.length, 256);
        compare(popup._current.actions[14].id, "action15");
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
        tryCompare(savedState(), "saveCount", 1, 10000);
        compare(JSON.parse(savedState().text).items.filter(function (n) { return !n.read; }).length, 0);
        savedState().saveCount = 0;
        historyChanges.clear();
        alerts.clearShown();
        compare(Notifications.all.length, 0);
        compare(Object.keys(Notifications.live).length, 0);
        compare(historyChanges.count, 1);
        tryCompare(savedState(), "saveCount", 1, 10000);
        compare(JSON.parse(savedState().text).items.length, 0);
    }
}
