pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../logic/NotificationLogic.js" as Logic
import qs.services

/**
 * Notification store: history grouped by app, read/unread,
 * snooze, dismiss, clear, actions and do not disturb. The list logic lives in
 * NotificationLogic.js (tested under node).
 *
 * Contract for the UI:
 *   items     newest first; snoozed items are left out until they wake
 *   groups    [{ appName, appIcon, count, unread, items }], newest group first
 *   apps      [{ appName, appIcon, count }] by app name (filter column)
 *   unreadCount, totalCount, snoozedCount
 *   markRead(id), snooze(id, minutes = 60), unsnoozeAll(),
 *   dismiss(id), invokeAction(id, actionId)
 *   markReadMany(ids), dismissMany(ids): one history change per bulk action
 *   dnd, setDnd(on)
 *   removed(id): the item left the store or the sender closed it
 *   arrived(item): a new notification that should pop up. With do not disturb
 *   on, only critical ones arrive (freedesktop convention); the others are
 *   still stored and count as unread, silently. A transient notification
 *   arrives too but is never stored in history (its id only works for
 *   invokeAction and dismiss while the sender keeps it open).
 *   updated(item): replaces an open or waiting pop-up without adding a copy.
 *
 * berri starts the server after saved state loads. Quickshell keeps an
 * existing owner of org.freedesktop.Notifications on a name conflict, logs
 * a warning and retries when that owner releases the name. berri can receive
 * notifications only after it owns the name.
 * Like every singleton, this one loads on first use, so
 * something in the shell must reference Notifications for the server to start.
 *
 * State file: ~/.local/state/berri-shell/notifications.json
 *   { dnd, items } with at most maxItems items. The old serverEnabled key is
 *   ignored. Actions are not saved (the sender is gone after a restart).
 */
Singleton {
    id: root

    readonly property int maxItems: Logic.limits.history
    readonly property int maxLive: Logic.limits.live
    readonly property real defaultSnoozeMinutes: 60

    property bool historyLoaded: false
    property bool dnd: false

    // Everything stored, snoozed items included.
    property var all: []
    property var items: []
    property var groups: []
    property var apps: []
    property int unreadCount: 0
    property int totalCount: 0
    property int snoozedCount: 0

    signal arrived(var item)
    signal updated(var item)
    /** An item left the store or its sender closed it; pop-ups drop it. */
    signal removed(string id)

    // Live D-Bus notifications by item id, for actions and closing the sender.
    property var live: Object.create(null)
    property var liveIdByServerId: Object.create(null)
    property var expiresAtById: Object.create(null)
    property int counter: 0
    property bool pendingCommit: false
    property bool pendingSave: false

    function setDnd(on: bool): void {
        if (root.dnd === on) return;
        root.dnd = on;
        root.save();
    }

    function markRead(id: string): void {
        root.commit(Logic.patch(root.all, id, { read: true }));
    }

    /** Marks the Alerts filter's items read in one history change. */
    function markReadMany(ids): void {
        var selected = new Set(ids);
        root.commit(root.all.map(function (n) {
            return selected.has(n.id) && !n.read ? Object.assign({}, n, { read: true }) : n;
        }));
    }

    function snooze(id: string, minutes: real): void {
        var m = minutes > 0 ? minutes : root.defaultSnoozeMinutes;
        root.commit(Logic.patch(root.all, id, { snoozedUntil: Date.now() + m * 60000 }));
    }

    /** Shows every snoozed item again now. */
    function unsnoozeAll(): void {
        root.commit(root.all.map(function (n) { return Object.assign({}, n, { snoozedUntil: 0 }); }));
    }

    function dismiss(id: string): void {
        root.closeLive(id);
        root.commit(Logic.remove(root.all, id));
    }

    /** Closes the Alerts filter's senders and removes its items in one change. */
    function dismissMany(ids): void {
        var selected = new Set(ids);
        ids.forEach(function (id) { root.closeLive(id); });
        root.commit(root.all.filter(function (n) { return !selected.has(n.id); }));
    }

    /** Runs a sender action, marks the item read and closes it at the sender. */
    function invokeAction(id: string, actionId: string): void {
        var n = root.live[id];
        if (n) {
            for (var i = 0; i < n.actions.length; i++) {
                if (n.actions[i].identifier === actionId) {
                    n.actions[i].invoke();
                    break;
                }
            }
            if (!n.resident) n.dismiss();
        }
        if (!n || !n.resident) root.removed(id);
        root.commit(Logic.patch(root.all, id, { read: true }));
    }

    function closeLive(id: string): void {
        var n = root.live[id];
        if (n) n.dismiss();
    }

    // Changes history now. Derived lists and serialization run once after a burst.
    function commit(next): void {
        var before = root.all;
        root.all = Logic.cap(next, root.maxItems);
        if (next.length > root.maxItems || next.length < before.length) {
            var kept = Object.create(null);
            root.all.forEach(function (n) { kept[n.id] = true; });
            before.forEach(function (n) {
                // A sender that becomes transient keeps its pop-up, but loses history.
                if (!kept[n.id] && !(root.live[n.id] && root.live[n.id].transient)) root.removed(n.id);
            });
        }
        root.pendingCommit = true;
        Qt.callLater(root.flush);
    }

    // Flushes one pending batch through the UI and saved-state boundary.
    function flush(): void {
        if (!root.pendingCommit) return;
        root.pendingCommit = false;
        root.refresh();
        root.save();
    }

    function refresh(): void {
        var now = Date.now();
        root.items = Logic.visible(root.all, now);
        root.groups = Logic.groupByApp(root.items);
        root.apps = Logic.appList(root.items);
        root.unreadCount = Logic.unreadCount(root.items);
        root.totalCount = root.items.length;
        root.snoozedCount = Logic.snoozedCount(root.all, now);
        var wake = Logic.nextWake(root.all, now);
        if (wake > 0) {
            wakeTimer.interval = Math.max(50, wake - now);
            wakeTimer.restart();
        } else {
            wakeTimer.stop();
        }
    }

    // Builds a store item from a Quickshell notification; the id is kept for a replaced one.
    function toItem(n, id: string): var {
        var icon = n.appIcon !== "" ? n.appIcon : n.desktopEntry;
        var image = String(n.image);
        if (icon === "" && image !== "" && image.indexOf("image://") !== 0) icon = image;
        var urgency = n.urgency === NotificationUrgency.Critical ? "critical"
            : n.urgency === NotificationUrgency.Low ? "low" : "normal";
        var actions = [];
        for (var i = 0; i < Math.min(n.actions.length, Logic.limits.actions); i++) {
            // Never truncate an action id: it must still identify the sender's action.
            if (n.actions[i].identifier.length <= Logic.limits.actionId)
                actions.push({ id: n.actions[i].identifier, label: n.actions[i].text });
        }
        return Logic.boundedItem({
            id: id, serverId: n.id, appName: n.appName !== "" ? n.appName : "Unknown", appIcon: icon,
            summary: n.summary, body: n.body, time: Date.now(), urgency: urgency,
            read: false, snoozedUntil: 0, actions: actions, transient: n.transient
        });
    }

    // Called for each notification the server receives.
    function receive(n): void {
        n.tracked = true;
        var known = root.liveIdByServerId[n.id];
        var reloaded = known === undefined && n.lastGeneration
            ? Logic.findReloaded(root.all, n.id,
                Logic.boundedText(n.appName !== "" ? n.appName : "Unknown", Logic.limits.appName),
                Logic.boundedText(n.summary, Logic.limits.summary)) : null;
        var isNew = known === undefined && reloaded === null;
        var id = known !== undefined ? known : reloaded !== null ? reloaded.id
            : "n" + Date.now().toString(36) + "-" + (root.counter++);
        var item = root.toItem(n, id);
        var old = root.all.filter(function (x) { return x.id === id; })[0];
        if (old) item = Logic.keepState(old, item);
        var firstSeen = root.live[id] !== n;
        if (firstSeen && root.live[id] === undefined) {
            var liveIds = Object.keys(root.live);
            if (liveIds.length >= root.maxLive) root.closeLive(liveIds[0]);
        }
        root.live[id] = n;
        if (firstSeen) {
            root.liveIdByServerId[n.id] = id;
            n.closed.connect(function (reason) {
                if (root.live[id] !== n) return;
                delete root.live[id];
                delete root.liveIdByServerId[n.id];
                delete root.expiresAtById[id];
                root.armExpireTimer();
                root.removed(id);
                if (reason === NotificationCloseReason.CloseRequested)
                    root.commit(Logic.remove(root.all, id));
            });
            var refreshItem = function () { if (root.live[id] === n) root.receive(n); };
            n.summaryChanged.connect(refreshItem);
            n.bodyChanged.connect(refreshItem);
            n.appIconChanged.connect(refreshItem);
            n.urgencyChanged.connect(refreshItem);
            n.actionsChanged.connect(refreshItem);
            n.appNameChanged.connect(refreshItem);
            n.desktopEntryChanged.connect(refreshItem);
            n.imageChanged.connect(refreshItem);
            n.transientChanged.connect(refreshItem);
            n.expireTimeoutChanged.connect(refreshItem);
        }
        root.setExpiry(id, n, item.urgency);
        if (!n.transient) root.commit(Logic.upsert(root.all, item));
        else if (old) root.commit(Logic.remove(root.all, id));
        if (!isNew) root.updated(item);
        if (isNew && Logic.shouldAlert(item.urgency, root.dnd)) root.arrived(item);
    }

    function setExpiry(id: string, n, urgency: string): void {
        if (urgency === "critical" || n.expireTimeout === 0) {
            delete root.expiresAtById[id];
        } else {
            var seconds = n.expireTimeout === -1 ? 5 : n.expireTimeout;
            root.expiresAtById[id] = Date.now() + seconds * 1000;
        }
        root.armExpireTimer();
    }

    function armExpireTimer(): void {
        var next = 0;
        Object.keys(root.expiresAtById).forEach(function (id) {
            var time = root.expiresAtById[id];
            if (next === 0 || time < next) next = time;
        });
        if (next === 0) {
            expireTimer.stop();
        } else {
            expireTimer.interval = Math.min(2147483647, Math.max(1, next - Date.now()));
            expireTimer.restart();
        }
    }

    function expireDue(): void {
        var now = Date.now();
        Object.keys(root.expiresAtById).forEach(function (id) {
            if (root.expiresAtById[id] > now) return;
            delete root.expiresAtById[id];
            var n = root.live[id];
            if (n) n.expire();
        });
        root.armExpireTimer();
    }

    // Defers serialization as well as the file write until the burst ends.
    function save(): void {
        root.pendingSave = true;
        saveTimer.restart();
    }

    // Serializes the latest history once after 300 ms without a save request.
    function writeSaved(): void {
        if (!root.pendingSave) return;
        root.pendingSave = false;
        saveTimer.stop();
        saved.save({ dnd: root.dnd, items: Logic.savedItems(root.all) });
    }

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: root.writeSaved()
    }

    // The store groups serialization; SavedState still makes the write atomic.
    SavedState {
        id: saved
        name: "notifications"
        waitMs: 0
        onLoaded: values => {
            var restored = Logic.readSaved(values);
            root.dnd = restored.dnd;
            root.all = Logic.cap(restored.items, root.maxItems);
            root.refresh();
            root.historyLoaded = true;
        }
    }

    // One timer for the nearest snoozed item; snoozed items come back without polling.
    Timer {
        id: wakeTimer
        onTriggered: {
            root.refresh();
        }
    }

    // One timer covers live notifications, including those hidden by do not disturb.
    Timer {
        id: expireTimer
        onTriggered: root.expireDue()
    }

    // Restore history and do not disturb before accepting new notifications.
    LazyLoader {
        active: root.historyLoaded

        NotificationServer {
            actionsSupported: true
            bodySupported: true
            bodyMarkupSupported: false
            imageSupported: true
            persistenceSupported: true
            onNotification: n => root.receive(n)
        }
    }
}
