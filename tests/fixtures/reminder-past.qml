import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.reminders
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items
import "../logic/Times.js" as Times

TestCase {
    name: "PastReminders"

    readonly property string oldStamp: "20260101T000000Z"

    // A reminder at a clock time, `hoursAgo` hours before now. Extra fields override.
    function reminderAt(uid, hoursAgo, fields) {
        var when = new Date(Date.now() - hoursAgo * 3600000);
        return Items.makeItem(Object.assign({ uid: uid, kind: "reminder", title: "Reminder " + uid,
            date: Times.dayKey(when), time: Times.pad(when.getHours()) + ":" + Times.pad(when.getMinutes()) }, fields || {}));
    }

    // Round-trips items without any disk or notification-server access.
    function calendarOf(items) {
        var document = Format.emptyCalendar();
        for (var i = 0; i < items.length; i++) document.items.push(items[i]);
        return Format.readCalendar(Format.writeCalendar(document));
    }

    // Seeds the real Calendar service with an in-memory calendar.
    function seed(items) {
        TestIo.reset();
        Calendar.ready = false;
        Calendar._stateRead = false;
        ReminderNotifier._started = false;
        ReminderNotifier._stateRead = false;
        ReminderNotifier._alreadyShown = [];
        ReminderNotifier._knownItems = ({});
        ReminderNotifier._lastCheck = Date.now();
        Calendar._calendars = { berri: { id: "berri", name: "berri", kind: "local", color: "accent",
            hidden: false, document: calendarOf(items || [reminderAt("past", 1)]) } };
        Calendar._order = ["berri"];
        Calendar._rebuild();
    }

    // Starts the notifier as if the saved state was read with this last check time.
    function start(lastCheck) {
        ReminderNotifier._lastCheck = lastCheck;
        ReminderNotifier._stateRead = true;
        Calendar.ready = true;
    }

    // Edits the stored items the way a save does, then lets the views rebuild.
    function edit(change) {
        change(Calendar._calendars.berri.document.items);
        Calendar._rebuild();
    }

    function titles() { return TestIo.downloads.map(function (argv) { return argv[argv.length - 2]; }); }

    // A calendar revision must deliver a newly saved past reminder once.
    function test_past_reminder_after_calendar_change() {
        seed();
        ReminderNotifier._started = true;
        Calendar._rebuild();
        compare(TestIo.downloads.length, 1);
        compare(TestIo.downloads[0].slice(-2), ["Reminder past", Calendar.allItems()[0].time]);
        compare(ReminderNotifier._alreadyShown.length, 1);
        Calendar._rebuild();
        compare(TestIo.downloads.length, 1);
    }

    // No state file: the first start sends no backlog, even for repeating reminders.
    function test_first_start_sends_no_backlog() {
        seed([reminderAt("daily", 1, { repeat: "daily", date: Times.dayKey(new Date(Date.now() - 6 * 86400000)),
            stamp: oldStamp })]);
        start(0);
        compare(TestIo.downloads.length, 0);
        verify(ReminderNotifier._lastCheck > 0);
        edit(function (items) { items[0].alarmMinutes = 10; });
        compare(TestIo.downloads.length, 0);
    }

    // A reminder saved while the shell was off is delivered once after the saved check time.
    function test_reminder_saved_while_off_is_delivered_once() {
        seed([reminderAt("late", 1)]);
        start(Date.now() - 1800000);
        compare(titles(), ["Reminder late"]);
        Calendar._rebuild();
        compare(titles(), ["Reminder late"]);
    }

    // A reminder that was already in the calendar at the last check is not sent again.
    function test_reminder_seen_before_the_last_check_is_not_resent() {
        seed([reminderAt("seen", 1, { stamp: oldStamp })]);
        start(Date.now() - 1800000);
        compare(TestIo.downloads.length, 0);
    }

    // A new alarm lead on a repeating reminder must not send its past occurrences.
    function test_alarm_edit_on_a_repeating_reminder_sends_nothing_old() {
        seed([reminderAt("daily", -3, { repeat: "daily", date: Times.dayKey(new Date(Date.now() - 8 * 86400000)),
            alarmMinutes: 5, stamp: oldStamp })]);
        start(Date.now() - 60000);
        compare(TestIo.downloads.length, 0);
        edit(function (items) { items[0].alarmMinutes = 10; });
        compare(TestIo.downloads.length, 0);
        edit(function (items) { items[0].time = Times.pad((new Date().getHours() + 4) % 24) + ":00"; });
        compare(TestIo.downloads.length, 0);
    }

    // A new repeating reminder, from an import or a feed, sends its latest past alert once.
    function test_new_repeating_reminder_sends_one_alert() {
        seed([reminderAt("old", -3, { stamp: oldStamp })]);
        start(Date.now() - 60000);
        compare(TestIo.downloads.length, 0);
        edit(function (items) {
            items.push(reminderAt("daily", 1, { repeat: "daily", date: Times.dayKey(new Date(Date.now() - 6 * 86400000)) }));
        });
        compare(titles(), ["Reminder daily"]);
        edit(function (items) { items[1].alarmMinutes = 10; });
        compare(titles(), ["Reminder daily"]);
    }

    // A flood of new past reminders sends only the newest ones and logs one summary line.
    function test_a_sweep_sends_at_most_the_limit_and_logs_the_rest() {
        seed([reminderAt("old", -3, { stamp: oldStamp })]);
        start(Date.now() - 60000);
        var many = [];
        for (var i = 0; i < 15; i++) many.push(reminderAt("n" + i, 1 + i * 0.05, { title: "Flood " + i }));
        ignoreWarning("ReminderNotifier: 15 reminders were due, 10 shown, 5 skipped");
        edit(function (items) { for (var i = 0; i < many.length; i++) items.push(many[i]); });
        compare(TestIo.downloads.length, ReminderNotifier.maxAlertsPerSweep);
        verify(titles().indexOf("Flood 0") >= 0);
        compare(titles().indexOf("Flood 14"), -1);
        edit(function () {});
        compare(TestIo.downloads.length, ReminderNotifier.maxAlertsPerSweep);
    }
}
