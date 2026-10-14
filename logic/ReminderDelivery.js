.pragma library

/** Pure rules for how a due reminder reaches the notification server and what happens when that fails. */

/** The pop-up shows at most this many action buttons (see notifications/NotificationPopup.qml). */
var popupActionLimit = 2;

/** The actions a reminder sends. Each one is shown by the pop-up and handled by ReminderNotifier.applyAction. */
var actions = [["plus15", "+15m"], ["done", "Done"]];

/**
 * The notify-send command for one due reminder. "--" ends the options, so a
 * title such as "--version" or "-h" stays text.
 */
function notifyCommand(reminder) {
    var argv = ["notify-send", "-a", "berri", "-i", "appointment-soon", "-u", "normal", "-t", "60000", "--wait"];
    for (var i = 0; i < actions.length && i < popupActionLimit; i++) argv.push("-A", actions[i][0] + "=" + actions[i][1]);
    argv.push("--", reminder.title || "Reminder", reminder.time);
    return argv;
}

/**
 * State after a delivery failed: the alert is not shown any more, and the
 * check time goes back to just before it so the next scan finds it again.
 * Returns { lastCheck, shown }.
 */
function afterFailedDelivery(state, key, dueMs) {
    return {
        lastCheck: Math.min(state.lastCheck, dueMs - 1),
        shown: state.shown.filter(function (k) { return k !== key; })
    };
}

/**
 * When to scan next. A due time that is already past (a failed delivery
 * waits for a retry) becomes now + retryMs. 0 stays 0 (nothing ahead).
 */
function nextWake(dueMs, nowMs, retryMs) {
    if (dueMs <= 0) return 0;
    return dueMs <= nowMs ? nowMs + retryMs : dueMs;
}

/** The time (ms) of an iCalendar UTC stamp such as "20261005T093000Z", or null when it has another form. */
function stampMs(stamp) {
    var m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(stamp || "");
    return m ? Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]) : null;
}

/** The last alert of each item. `alerts` is oldest first, as `Items.dueBetween` returns it. */
function latestPerItem(alerts) {
    var last = {};
    for (var i = 0; i < alerts.length; i++) last[alerts[i].calendarId + "|" + alerts[i].uid] = alerts[i];
    return alerts.filter(function (alert) { return last[alert.calendarId + "|" + alert.uid] === alert; });
}

/** The newest `limit` alerts of an oldest-first list, and how many older ones are left out. */
function newestAlerts(alerts, limit) {
    var skipped = Math.max(0, alerts.length - limit);
    return { shown: alerts.slice(skipped), skipped: skipped };
}
