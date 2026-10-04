import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
import qs.tabs.calendar
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "CalendarReadSafety"
    width: 900
    height: 600

    readonly property string berriPath: Calendar.defaultPath
    readonly property string feed: "https://example.test/feed"

    SignalSpy { id: failureSpy; target: Calendar; signalName: "saveFailed" }

    function calendarFiles() {
        return Calendar.children.find(function (child) { return child instanceof CalendarFiles; });
    }

    // One calendar text with one event.
    function savedText() {
        return Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
    }

    // Start the actual service with only the local calendar, not read yet.
    function init() {
        TestIo.reset();
        failureSpy.clear();
        calendarFiles().paths = [];
        Quickshell.detached = [];
        Calendar.ready = false;
        Calendar._stateRead = false;
        Calendar.lastError = "";
        Calendar._calendars = { berri: Calendar._newMeta("berri", "local", "berri", "berri.ics", "") };
        Calendar._order = ["berri"];
        Calendar._rebuild();
    }

    // Let the file readers run for the calendar list.
    function startReading() { Calendar._syncPaths(); }

    function test_a_denied_first_read_refuses_edits_and_keeps_the_file() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        TestIo.deniedReads[berriPath] = true;
        startReading();
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], original);
        compare(TestIo.writes.length, 0);
        compare(failureSpy.count, 1);
        compare(failureSpy.signalArguments[0][0], "Could not read berri");
        compare(Calendar.lastError, "Could not read berri");
        compare(Calendar.update(Items.itemKey("berri", "kept"), { title: "Changed" }), false);
        compare(Calendar.remove(Items.itemKey("berri", "kept")), false);
        compare(Calendar.setDone(Items.itemKey("berri", "kept"), true), false);
        compare(TestIo.writes.length, 0);
    }

    function test_edits_work_after_a_successful_retry() {
        TestIo.texts[berriPath] = savedText();
        TestIo.deniedReads[berriPath] = true;
        startReading();
        compare(Calendar.add({ title: "Before retry", date: "2026-10-06" }), false);
        TestIo.deniedReads = ({});
        compare(Calendar.add({ title: "After retry", date: "2026-10-07" }), true);
        const saved = Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title).sort();
        compare(saved, ["After retry", "Kept"]);
        compare(Calendar.lastError, "");
    }

    function test_a_missing_calendar_starts_empty_and_accepts_an_edit() {
        startReading();
        compare(Calendar.add({ title: "First", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["First"]);
    }

    // Subscribe to the test feed through the service and finish its download.
    function subscribeFeed(records) {
        Calendar.subscribe(feed, "blue");
        const download = TestIo.downloads[TestIo.downloads.length - 1];
        TestIo.texts["/subscribe.json"] = JSON.stringify({ name: "Feed", records: records });
        download.stdout.text = "/subscribe.json";
        download.exited(0, 0);
        return Calendar._order.filter(id => id !== "berri")[0];
    }

    function record(title) { return { uid: title, kind: "event", title: title, date: "2026-10-05" }; }

    function test_a_removed_subscription_stops_its_download_and_ignores_the_late_result() {
        const id = subscribeFeed([record("Old")]);
        Calendar.refresh(id);
        const held = TestIo.downloads[TestIo.downloads.length - 1];
        compare(held.running, true);
        compare(Calendar.removeCalendar(id), true);
        compare(held.running, false);
        TestIo.texts["/late.json"] = JSON.stringify({ name: "Feed", records: [record("Late")] });
        held.stdout.text = "/late.json";
        held.exited(0, 0);
        compare(Calendar.calendars.length, 1);
        compare(calendarFiles().paths.length, 1);
    }

    function test_a_new_subscription_ignores_results_of_the_removed_one() {
        const id = subscribeFeed([record("Old")]);
        Calendar.refresh(id);
        const held = TestIo.downloads[TestIo.downloads.length - 1];
        Calendar.removeCalendar(id);
        const again = subscribeFeed([record("New")]);
        compare(again, id);
        TestIo.texts["/late.json"] = JSON.stringify({ name: "Feed", records: [record("Late")] });
        held.stdout.text = "/late.json";
        held.exited(0, 0);
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["New"]);
    }
}
