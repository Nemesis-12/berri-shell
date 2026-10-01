pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/CalendarIcs.js" as Ics
import qs.common
import qs.services

/**
 * Shows a desktop notification when a reminder is due, with the actions
 * +15m, +1d and Done. Works with the dashboard closed. shell.qml keeps
 * this singleton active.
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

    readonly property string statePath: (Quickshell.env("HOME") || "") + "/.local/state/berri-shell/reminders.json"
    readonly property int maxWaitMs: 30000
    readonly property real missedWindowMs: 7 * 86400000
    readonly property real horizonDays: 400

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
        var due = Ics.dueBetween(Calendar.allItems(), from, now);
        for (var i = 0; i < due.length; i++) {
            var key = Ics.itemKey(due[i].calendarId, due[i].uid) + "|" + due[i].dueMs;
            var keyWithoutCalendar = due[i].uid + "|" + due[i].dueMs;
            if (_alreadyShown.indexOf(key) >= 0 || _alreadyShown.indexOf(keyWithoutCalendar) >= 0) continue;
            _alreadyShown.push(key);
            _notify(due[i]);
        }
        _lastCheck = now;
        var cutoff = now - missedWindowMs;
        _alreadyShown = _alreadyShown.filter(function (k) { return +k.slice(k.lastIndexOf("|") + 1) > cutoff; });
        _save();
        _arm();
    }

    function _arm(): void {
        var next = Ics.nextDueMs(Calendar.allItems(), _lastCheck, horizonDays);
        _nextDueMs = next === null ? 0 : next;
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
            if (root._nextDueMs > 0 && now >= root._nextDueMs) root._sweep(root._lastCheck, now);
            else root._wait();
        }
    }

    function _notify(reminder: var): void {
        notifierComponent.createObject(root, { reminder: reminder });
    }

    /** Applies the action the person chose in the notification. */
    function applyAction(action: string, calendarId: string, uid: string, occurrenceDate: string): void {
        var key = Ics.itemKey(calendarId, uid);
        if (action === "plus15") Calendar.snooze(key, occurrenceDate, 15);
        else if (action === "plus1d") Calendar.snooze(key, occurrenceDate, "1d");
        else if (action === "done") Calendar.setDone(key, true, occurrenceDate);
    }

    // One notify-send per alert. --wait prints the chosen action when the notification closes.
    Component {
        id: notifierComponent
        Process {
            id: proc
            required property var reminder
            running: true
            command: ["notify-send", "-a", "berri", "-i", "appointment-soon", "-u", "normal", "-t", "60000", "--wait",
                "-A", "plus15=+15m", "-A", "plus1d=+1d", "-A", "done=Done",
                reminder.title || "Reminder", reminder.time]
            stdout: StdioCollector {
                onStreamFinished: root.applyAction(text.trim(), proc.reminder.calendarId, proc.reminder.uid, proc.reminder.occurrenceDate)
            }
            onExited: proc.destroy()
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
