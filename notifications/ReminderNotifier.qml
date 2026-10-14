pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/CalendarItems.js" as Items
import "../logic/ReminderDelivery.js" as Delivery
import qs.services

/**
 * Shows a desktop notification when a reminder is due, with the actions
 * +15m and Done (the pop-up shows two buttons). Works with the dashboard
 * closed. shell.qml keeps this singleton active. The notification goes to
 * org.freedesktop.Notifications, which berri owns, so it shows in Alerts and
 * as a pop-up. A failed delivery is tried again every 30 s.
 *
 * One Timer waits for the nearest due time. It starts again after every
 * calendar change and every alert. The Timer never waits more than 30 s: a
 * Timer does not count the time asleep, so after suspend or a clock change
 * the next tick checks the real time.
 *
 * ~/.local/state/berri-shell/reminders.json keeps the time of the last check
 * and the alerts already shown ({ lastCheck, shown: [key] }). A sweep looks
 * only at alerts due since the last check, so a new alarm lead or time on an
 * old repeating reminder sends nothing old. A reminder that is new since the
 * last check (saved late, imported, or added while the shell was off) shows
 * its latest alert from the past week once. The first start has no last check
 * and shows no backlog. One sweep shows at most `maxAlertsPerSweep` alerts
 * and logs one line for the rest. Older reminders stay visible in the calendar.
 */
Singleton {
    id: root

    readonly property int maxWaitMs: 30000
    readonly property real missedWindowMs: 7 * 86400000
    readonly property real horizonDays: 400
    readonly property int retryMs: 30000
    readonly property int maxAlertsPerSweep: 10

    property bool _started: false
    property bool _stateRead: false
    property real _lastCheck: 0
    property var _alreadyShown: []      // keys like "uid|dueMs"
    property var _knownItems: ({})      // file UIDs seen since start, also of calendars now hidden
    property real _nextDueMs: 0  // 0 = no reminder ahead

    Connections {
        target: Calendar
        function onRevisionChanged() { root._onCalendarChanged(); }
        function onReadyChanged() { root._begin(); }
    }

    function _begin(): void {
        if (_started || !_stateRead || !Calendar.ready) return;
        _started = true;
        var now = Date.now();
        // First run: nothing to catch up, so every item counts as seen. Later runs:
        // an item saved after the last check is new.
        var firstRun = _lastCheck <= 0;
        _knownItems = {};
        var items = Calendar.allItems();
        _rememberItems(items.filter(function (item) {
            var savedAt = Delivery.stampMs(item.stamp);
            return firstRun || savedAt === null || savedAt <= _lastCheck;
        }));
        if (firstRun) _lastCheck = now;
        _sweep(now);
    }

    // The calendar changed: alerts just due show now, and new items show their latest past alert.
    function _onCalendarChanged(): void {
        if (!_started) return;
        _sweep(Date.now());
    }

    // The file UID, without the calendar: a duplicate in another calendar is the same reminder.
    function _itemKey(item: var): string { return item.uid; }

    // Adds to the known items and never removes: a hidden calendar, or a deleted copy of a duplicate, does not make its reminder new later.
    function _rememberItems(items: var): void {
        for (var i = 0; i < items.length; i++) _knownItems[_itemKey(items[i])] = true;
    }

    // Shows the unshown alerts due since the last check and the latest alert of each new item, saves the state, waits for the next.
    function _sweep(now: real): void {
        var items = Calendar.allItems();
        var oldest = now - missedWindowMs;
        var seen = items.filter(function (item) { return _knownItems[_itemKey(item)]; });
        var fresh = items.filter(function (item) { return !_knownItems[_itemKey(item)]; });
        var due = Items.dueBetween(seen, Math.max(_lastCheck, oldest), now)
            .concat(Delivery.latestPerItem(Items.dueBetween(fresh, oldest, now)))
            .sort(function (a, b) { return a.dueMs - b.dueMs; });
        _rememberItems(items);
        var unshown = [];
        for (var i = 0; i < due.length; i++) {
            var key = due[i].uid + "|" + due[i].dueMs;
            if (_alreadyShown.indexOf(key) >= 0) continue;
            _alreadyShown.push(key);
            unshown.push({ alert: due[i], key: key });
        }
        // Skipped alerts stay in the shown keys, so a later sweep does not send them.
        var sent = Delivery.newestAlerts(unshown, maxAlertsPerSweep);
        if (sent.skipped > 0)
            console.warn("ReminderNotifier: " + unshown.length + " reminders were due, " + sent.shown.length + " shown, " + sent.skipped + " skipped");
        for (var s = 0; s < sent.shown.length; s++) _notify(sent.shown[s].alert, sent.shown[s].key);
        _lastCheck = now;
        var cutoff = now - missedWindowMs;
        _alreadyShown = _alreadyShown.filter(function (k) { return +k.slice(k.lastIndexOf("|") + 1) > cutoff; });
        _save();
        _arm();
    }

    function _arm(): void {
        var next = Items.nextDueMs(Calendar.allItems(), _lastCheck, horizonDays);
        _nextDueMs = Delivery.nextWake(next === null ? 0 : next, Date.now(), retryMs);
        _wait();
    }

    function _wait(): void {
        var left = _nextDueMs > 0 ? _nextDueMs - Date.now() : maxWaitMs;
        timer.interval = Math.max(50, Math.min(maxWaitMs, left));
        timer.restart();
    }

    Timer {
        id: timer
        onTriggered: {
            var now = Date.now();
            if (root._nextDueMs > 0 && now >= root._nextDueMs) root._sweep(now);
            else root._wait();
        }
    }

    // Uses berri's existing desktop notification route for saved-state errors.
    Connections {
        target: Calendar
        function onSaveFailed(message) {
            if (!Calendar.saveErrorShown) root._showSaveError("Calendar not saved", message);
        }
    }

    Connections {
        target: Wallpapers
        function onSaveFailed(message) {
            root._showSaveError("Wallpaper settings not saved", message);
        }
    }

    function _showSaveError(title: string, message: string): void {
        saveErrorComponent.createObject(root, { title: title, message: message });
    }

    Component {
        id: saveErrorComponent
        Process {
            id: errorProc
            required property string title
            required property string message
            running: true
            command: ["notify-send", "-a", "berri", "-i", "dialog-error", "-u", "normal", title, message]
            onExited: errorProc.destroy()
        }
    }

    function _notify(reminder: var, key: string): void {
        notifierComponent.createObject(root, { reminder: reminder, key: key });
    }

    // The delivery failed: the alert counts as not shown, so the next scan finds it again.
    function _deliveryFailed(key: string, dueMs: real): void {
        var state = Delivery.afterFailedDelivery({ lastCheck: _lastCheck, shown: _alreadyShown }, key, dueMs);
        _lastCheck = state.lastCheck;
        _alreadyShown = state.shown;
        _save();
        _arm();
    }

    /** Applies the action the person chose in the notification. */
    function applyAction(action: string, calendarId: string, uid: string, occurrenceDate: string): void {
        var key = Items.itemKey(calendarId, uid);
        if (action === "plus15") Calendar.snooze(key, occurrenceDate, 15);
        else if (action === "done") Calendar.setDone(key, true, occurrenceDate);
    }

    // One notify-send per alert. --wait prints the chosen action when the notification closes.
    Component {
        id: notifierComponent
        Process {
            id: proc
            required property var reminder
            required property string key
            running: true
            command: Delivery.notifyCommand(reminder)
            stdout: StdioCollector {
                onStreamFinished: root.applyAction(text.trim(), proc.reminder.calendarId, proc.reminder.uid, proc.reminder.occurrenceDate)
            }
            onExited: exitCode => {
                if (exitCode !== 0) root._deliveryFailed(proc.key, proc.reminder.dueMs);
                proc.destroy();
            }
        }
    }

    // ---- saved state

    SavedState {
        id: savedReminders
        name: "reminders"
        defaults: ({ lastCheck: 0, shown: [] })
        onLoaded: values => {
            root._lastCheck = +values.lastCheck || 0;
            root._alreadyShown = Array.isArray(values.shown) ? values.shown : [];
            root._stateRead = true;
            root._begin();
        }
    }

    function _save(): void {
        savedReminders.save({ lastCheck: _lastCheck, shown: _alreadyShown });
    }
}
