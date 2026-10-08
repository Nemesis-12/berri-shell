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
 * and the alerts already shown ({ lastCheck, shown: [key] }). Reminders that
 * fell due while the shell was off show once at start (up to a week back).
 */
Singleton {
    id: root

    readonly property int maxWaitMs: 30000
    readonly property real missedWindowMs: 7 * 86400000
    readonly property real horizonDays: 400
    readonly property int retryMs: 30000

    property bool _started: false
    property bool _stateRead: false
    property real _lastCheck: 0
    property var _alreadyShown: []      // keys like "[calendarId, uid]|dueMs"
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
        // First run: nothing to catch up. Later runs: from the last check.
        var from = _lastCheck > 0 ? Math.max(_lastCheck, now - missedWindowMs) : now;
        _sweep(from, now);
    }

    // The calendar changed: alerts that are just due show now, then wait for the next one.
    function _onCalendarChanged(): void {
        if (!_started) return;
        var now = Date.now();
        _sweep(Math.max(_lastCheck, now - 60000), now);
    }

    // Shows every unshown alert due in (from, now], saves the state, waits for the next.
    function _sweep(from: real, now: real): void {
        var due = Items.dueBetween(Calendar.allItems(), from, now);
        for (var i = 0; i < due.length; i++) {
            var key = Items.itemKey(due[i].calendarId, due[i].uid) + "|" + due[i].dueMs;
            var keyWithoutCalendar = due[i].uid + "|" + due[i].dueMs;
            if (_alreadyShown.indexOf(key) >= 0 || _alreadyShown.indexOf(keyWithoutCalendar) >= 0) continue;
            _alreadyShown.push(key);
            _notify(due[i], key);
        }
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
            if (root._nextDueMs > 0 && now >= root._nextDueMs) root._sweep(Math.max(root._lastCheck, now - root.missedWindowMs), now);
            else root._wait();
        }
    }

    // A failed calendar save (for example from a reminder action) with no Calendar tab open: tell the person.
    Connections {
        target: Calendar
        function onSaveFailed(message) {
            if (!Calendar.saveErrorShown) saveErrorComponent.createObject(root, { message: message });
        }
    }

    Component {
        id: saveErrorComponent
        Process {
            id: errorProc
            required property string message
            running: true
            command: ["notify-send", "-a", "berri", "-i", "dialog-error", "-u", "normal", "Calendar not saved", message]
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
