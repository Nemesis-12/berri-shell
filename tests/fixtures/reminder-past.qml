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

    // Round-trips an overdue reminder without any disk or notification-server access.
    function overdue() {
        var when = new Date(Date.now() - 3600000);
        var document = Format.emptyCalendar();
        document.items.push(Items.makeItem({ uid: "past", kind: "reminder", title: "Past reminder",
            date: Times.dayKey(when), time: Times.pad(when.getHours()) + ":" + Times.pad(when.getMinutes()) }));
        return Format.readCalendar(Format.writeCalendar(document));
    }

    // Seeds the real Calendar service with an in-memory calendar.
    function seed() {
        TestIo.reset();
        Calendar.ready = false;
        Calendar._stateRead = false;
        ReminderNotifier._started = false;
        ReminderNotifier._stateRead = false;
        ReminderNotifier._alreadyShown = [];
        ReminderNotifier._lastCheck = Date.now();
        Calendar._calendars = { berri: { id: "berri", name: "berri", kind: "local", color: "accent",
            hidden: false, document: overdue() } };
        Calendar._order = ["berri"];
        Calendar._rebuild();
    }

    // A calendar revision must deliver a newly saved past reminder once.
    function test_past_reminder_after_calendar_change() {
        seed();
        ReminderNotifier._started = true;
        Calendar._rebuild();
        compare(TestIo.downloads.length, 1);
        compare(TestIo.downloads[0].slice(-2), ["Past reminder", Calendar.allItems()[0].time]);
        compare(ReminderNotifier._alreadyShown.length, 1);
        Calendar._rebuild();
        compare(TestIo.downloads.length, 1);
    }

    // First startup must also deliver an unshown reminder from the past week.
    function test_past_reminder_on_first_start() {
        seed();
        ReminderNotifier._lastCheck = 0;
        ReminderNotifier._stateRead = true;
        Calendar.ready = true;
        compare(TestIo.downloads.length, 1);
        compare(TestIo.downloads[0].slice(-2), ["Past reminder", Calendar.allItems()[0].time]);
    }
}
