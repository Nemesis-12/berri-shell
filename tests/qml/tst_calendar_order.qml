import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "CalendarOrder"
    width: 900
    height: 600

    readonly property string day: "2026-10-05"
    readonly property string kept: Items.itemKey("berri", "kept")

    // Logs each change signal with the titles the views would read at that moment.
    // A title list that already shows the edit proves the views were rebuilt first.
    Connections {
        target: Calendar
        function onRevisionChanged() {
            TestIo.note("revision:" + Calendar.itemsOn(tests.day).map(item => item.title).sort().join(","));
        }
        function onSaveFailed(message) { TestIo.note("saveFailed"); }
    }

    function calendarFiles() {
        return Calendar.children.find(function (child) { return child instanceof CalendarFiles; });
    }

    // The service reads a local calendar that holds one event, "Kept".
    function init() {
        TestIo.reset();
        calendarFiles().paths = [];
        Calendar.ready = false;
        Calendar._stateRead = false;
        Calendar.lastError = "";
        Calendar._calendars = { berri: Calendar._newMeta("berri", "local", "berri", "berri.ics", "") };
        Calendar._order = ["berri"];
        Calendar._rebuild();
        TestIo.texts[Calendar.defaultPath] = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: day })] }));
        Calendar._syncPaths();
        TestIo.events = [];
    }

    function test_an_added_item_is_saved_then_rebuilt_then_signalled() {
        compare(Calendar.add({ title: "New", date: day }), true);
        compare(TestIo.events, ["write", "revision:Kept,New"]);
    }

    function test_an_updated_item_is_saved_then_rebuilt_then_signalled() {
        compare(Calendar.update(kept, { title: "Changed" }), true);
        compare(TestIo.events, ["write", "revision:Changed"]);
    }

    function test_a_removed_item_is_saved_then_rebuilt_then_signalled() {
        compare(Calendar.remove(kept), true);
        compare(TestIo.events, ["write", "revision:"]);
    }

    // A failed write puts the old file text back, rebuilds the views, and only then reports the failure.
    function test_a_failed_add_is_undone_and_rebuilt_before_the_failure_signal() {
        TestIo.failWrite = true;
        compare(Calendar.add({ title: "New", date: day }), false);
        compare(TestIo.events, ["write-failed", "revision:Kept", "saveFailed"]);
        compare(Calendar.lastError, "Could not save berri: Permission denied");
    }

    function test_a_failed_update_is_undone_and_rebuilt_before_the_failure_signal() {
        TestIo.failWrite = true;
        compare(Calendar.update(kept, { title: "Changed" }), false);
        compare(TestIo.events, ["write-failed", "revision:Kept", "saveFailed"]);
    }

    function test_a_failed_remove_is_undone_and_rebuilt_before_the_failure_signal() {
        TestIo.failWrite = true;
        compare(Calendar.remove(kept), false);
        compare(TestIo.events, ["write-failed", "revision:Kept", "saveFailed"]);
    }
}
