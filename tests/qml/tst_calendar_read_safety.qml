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
    CalendarDisk { id: helperDisk; store: Calendar; files: tests.calendarFiles() }

    function calendarFiles() {
        return Calendar.children.find(function (child) { return child instanceof CalendarFiles; });
    }

    // One calendar text with one event.
    function savedText() {
        return Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
    }

    // One repeat has an occurrence changed by its source file.
    function changedOccurrenceText() {
        return ["BEGIN:VCALENDAR", "VERSION:2.0",
            "BEGIN:VEVENT", "UID:series", "SUMMARY:Master", "DTSTART:20261001T090000",
            "DTEND:20261001T100000", "RRULE:FREQ=DAILY;COUNT=4", "END:VEVENT",
            "BEGIN:VEVENT", "UID:series", "RECURRENCE-ID:20261002T090000", "SUMMARY:Changed",
            "DTSTART:20261009T150000", "DTEND:20261009T160000", "END:VEVENT",
            "END:VCALENDAR", ""].join("\r\n");
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

    // An add must wait for the first read, then keep the items from that read.
    function test_add_before_the_first_read_keeps_all_old_items() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        TestIo.heldReads[berriPath] = true;
        startReading();
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], original);
        compare(TestIo.writes.length, 0);
        delete TestIo.heldReads[berriPath];
        TestIo.readers[berriPath].loaded();
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title).sort(), ["Kept", "New"]);
    }

    function test_moving_a_changed_repeat_keeps_its_displayed_fields() {
        const text = changedOccurrenceText();
        TestIo.texts[berriPath] = text;
        Calendar.acceptCalendarRead(berriPath, text, false);
        const uid = Items.itemKey("berri", "series");
        const occurrence = Calendar.itemsOn("2026-10-09").find(item => item.uid === uid);
        compare([occurrence.title, occurrence.time, occurrence.end], ["Changed", "15:00", "16:00"]);
        compare(Calendar.move(uid, occurrence.occurrenceDate, "2026-11-02", {}), true);
        const moved = Calendar.itemsOn("2026-11-02").find(item => item.uid !== uid);
        compare([moved.title, moved.time, moved.end], ["Changed", "15:00", "16:00"]);
    }

    // A file color change must retry the read before it changes the cached items.
    function test_whole_calendar_color_after_a_failed_read_writes_nothing() {
        const meta = Calendar._addCalendar("work", "file", "Work", "work.ics", "", "blue");
        const text = savedText().replace("END:VEVENT", "X-BERRI-COLOR:red\r\nEND:VEVENT");
        TestIo.texts[meta.path] = text;
        startReading();
        TestIo.deniedReads[meta.path] = true;
        calendarFiles().read(meta.path, "", true);
        compare(Calendar.applyColorToCalendar("work", "green"), false);
        compare(TestIo.texts[meta.path], text);
        compare(TestIo.writes.length, 0);
        compare(Calendar.calendars.find(calendar => calendar.id === "work").color, "blue");
        compare(Calendar.getItem(Items.itemKey("work", "kept")).color, "red");
        compare(failureSpy.count, 1);
        compare(Calendar.prepareCalendarWrite(meta.path), null);
        // A successful retry takes current content before clearing its own colors.
        TestIo.deniedReads = ({});
        TestIo.texts[meta.path] = text.replace("SUMMARY:Kept", "SUMMARY:Current");
        compare(Calendar.applyColorToCalendar("work", "green"), true);
        compare(Format.readCalendar(TestIo.texts[meta.path]).items.map(item => item.title), ["Current"]);
        verify(!TestIo.texts[meta.path].includes("X-BERRI-COLOR:red"));
    }

    // Helpers get no write text for unread, unknown or subscription calendars.
    function test_write_preparation_refuses_an_unread_calendar() {
        compare(Calendar.prepareCalendarWrite(berriPath), null);
        compare(helperDisk.commitCalendar(berriPath), false);
        compare(Calendar.prepareCalendarWrite(Calendar.dir + "/unknown.ics"), null);
        TestIo.texts[berriPath] = savedText();
        startReading();
        compare(Calendar.prepareCalendarWrite(berriPath).previousText, savedText());
        compare(helperDisk.commitCalendar(berriPath), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["Kept"]);
    }

    function test_broken_read_shows_an_error_and_refuses_all_saves_data() {
        return [
            { tag: "empty", text: "" },
            { tag: "invalid", text: "temporarily empty while saving" },
            { tag: "unclosed", text: "BEGIN:VCALENDAR\nBEGIN:VTIMEZONE\n" + savedText().split("BEGIN:VCALENDAR\r\n")[1] },
            { tag: "mismatched", text: savedText().replace("END:VEVENT", "END:VTODO") },
            { tag: "invalid line", text: savedText().replace("SUMMARY:Kept", "broken line") },
            { tag: "extra text", text: savedText() + "garbage" }
        ];
    }

    // Bad external text keeps the last valid display but cannot become a writable document.
    function test_broken_read_shows_an_error_and_refuses_all_saves(data) {
        TestIo.texts[berriPath] = savedText();
        startReading();
        TestIo.texts[berriPath] = data.text;
        calendarFiles().read(berriPath, data.text, false);
        compare(Calendar.calendars[0].error, data.text === "" ? "Calendar file is empty: berri" : "Could not read berri");
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["Kept"]);
        const uid = Items.itemKey("berri", "kept");
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(Calendar.update(uid, { title: "Changed" }), false);
        compare(Calendar.move(uid, "2026-10-05", "2026-10-06", {}), false);
        compare(Calendar.remove(uid), false);
        compare(Calendar.setDone(uid, true), false);
        compare(Calendar.prepareCalendarWrite(berriPath), null);
        compare(TestIo.texts[berriPath], data.text);
        compare(TestIo.writes.length, 0);
        TestIo.texts[berriPath] = savedText();
        compare(Calendar.update(uid, { title: "Recovered" }), true);
        compare(Calendar.calendars[0].error, "");
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["Recovered"]);
    }

    // No cached document is made from a broken first read or a broken import.
    function test_broken_first_read_and_import_are_refused() {
        const broken = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Lost\nEND:VCALENDAR";
        TestIo.texts[berriPath] = broken;
        startReading();
        compare(Calendar.calendars[0].error, "Could not read berri");
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        TestIo.texts["/broken.ics"] = broken;
        compare(Calendar.importFile("/broken.ics"), "");
        compare(Calendar.lastError, "Not a calendar file");
        compare(TestIo.writes.length, 0);
    }

    // A missing non-local file is a failed read, even with no cached items.
    function test_missing_known_calendar_is_never_empty_and_writable_data() {
        return [{ tag: "unread file", loaded: false },
            { tag: "loaded file", loaded: true }];
    }

    function test_missing_known_calendar_is_never_empty_and_writable(data) {
        const meta = Calendar._addCalendar("work", "file", "Work", "work.ics", "", "blue");
        if (data.loaded) {
            TestIo.texts[meta.path] = savedText();
            startReading();
            delete TestIo.texts[meta.path];
            // Reload the real reader through its file-change signal.
            const reader = TestIo.readers[meta.path];
            verify(reader !== undefined);
            reader.fileChanged();
        } else startReading();
        compare(Calendar.calendars.find(calendar => calendar.id === meta.id).error, "Could not read " + meta.name);
        compare(Calendar.add({ title: "New", date: "2026-10-06", calendarId: meta.id }), false);
        compare(Calendar.prepareCalendarWrite(meta.path), null);
        compare(TestIo.texts[meta.path], undefined);
        compare(TestIo.writes.length, 0);
        TestIo.texts[meta.path] = savedText();
        compare(Calendar.add({ title: "After read", date: "2026-10-06", calendarId: meta.id }), true);
        compare(Format.readCalendar(TestIo.texts[meta.path]).items.map(item => item.title).sort(), ["After read", "Kept"]);
    }

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

    function test_a_failed_reload_refuses_edits_until_a_read_succeeds() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        startReading();
        TestIo.deniedReads[berriPath] = true;
        calendarFiles().read(berriPath, "", true);
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], original);
        compare(TestIo.writes.length, 0);
        compare(failureSpy.count, 1);
        compare(Calendar.lastError, "Could not read berri");
        TestIo.deniedReads = ({});
        calendarFiles().read(berriPath, original, false);
        compare(Calendar.add({ title: "After read", date: "2026-10-07" }), true);
        const saved = Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title).sort();
        compare(saved, ["After read", "Kept"]);
    }

    // Deletion before the watch arrives must recover without a later watch event.
    function test_local_deletion_before_watch_allows_the_next_edit() {
        TestIo.texts[berriPath] = savedText();
        startReading();
        delete TestIo.texts[berriPath];
        compare(Calendar.add({ title: "Refused stale edit", date: "2026-10-06" }), false);
        compare(Calendar.calendars[0].error, "");
        compare(Calendar.itemsOn("2026-10-05"), []);
        compare(Calendar.add({ title: "After deletion", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["After deletion"]);
        compare(TestIo.texts[berriPath + ".bak"], undefined);
    }

    // A known missing local file must still refuse a later permission failure.
    function test_new_local_calendar_refuses_a_denied_read_before_save() {
        startReading();
        TestIo.deniedReads[berriPath] = true;
        compare(Calendar.add({ title: "Denied", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], undefined);
        compare(Calendar.calendars[0].error, "Could not read berri");
        TestIo.deniedReads = ({});
        compare(Calendar.add({ title: "Recovered", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["Recovered"]);
    }

    // A local retry distinguishes a missing file from a denied read.
    function test_missing_local_file_recovers_after_a_failed_read() {
        TestIo.deniedReads[berriPath] = true;
        startReading();
        compare(Calendar.add({ title: "Denied", date: "2026-10-06" }), false);
        TestIo.deniedReads = ({});
        compare(Calendar.add({ title: "Recovered", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["Recovered"]);
        compare(Calendar.calendars[0].error, "");
    }

    function test_a_missing_calendar_starts_empty_and_accepts_an_edit() {
        startReading();
        compare(Calendar.add({ title: "First", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["First"]);
    }

    // Deleting the local file starts an empty calendar even after a successful read.
    function test_deleted_local_file_accepts_a_new_event() {
        TestIo.texts[berriPath] = savedText();
        startReading();
        delete TestIo.texts[berriPath];
        TestIo.readers[berriPath].fileChanged();
        compare(Calendar.calendars[0].error, "");
        compare(Calendar.itemsOn("2026-10-05"), []);
        compare(Calendar.add({ title: "After deletion", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["After deletion"]);
        compare(TestIo.writes, [berriPath]);
    }

    // The disk can change before its watch notification reaches Calendar.
    function test_external_change_refuses_edits_and_shows_current_content_data() {
        return [
            { tag: "add", edit: () => Calendar.add({ title: "Lost", date: "2026-10-06" }) },
            { tag: "update", edit: () => Calendar.update(Items.itemKey("work", "kept"), { title: "Lost" }) },
            { tag: "move", edit: () => Calendar.move(Items.itemKey("work", "kept"), "2026-10-05", "2026-10-06", {}) },
            { tag: "remove", edit: () => Calendar.remove(Items.itemKey("work", "kept")) },
            { tag: "color", edit: () => Calendar.applyColorToCalendar("work", "green") },
            { tag: "helper", edit: () => helperDisk.commitCalendar(Calendar.dir + "/work.ics") }
        ];
    }

    function test_external_change_refuses_edits_and_shows_current_content(data) {
        const meta = Calendar._addCalendar("work", "file", "Work", "work.ics", "", "blue");
        const original = savedText().replace("END:VEVENT", "X-BERRI-COLOR:red\r\nEND:VEVENT");
        TestIo.texts[meta.path] = original;
        TestIo.texts[berriPath] = original;
        startReading();
        const path = data.tag === "add" ? berriPath : meta.path;
        const current = original.replace("SUMMARY:Kept", "SUMMARY:External");
        TestIo.texts[path] = current;
        compare(data.edit(), false);
        compare(TestIo.texts[path], current);
        compare(TestIo.writes, []);
        compare(Calendar.getItem(Items.itemKey(data.tag === "add" ? "berri" : "work", "kept")).title, "External");
        compare(Calendar.itemsOn("2026-10-06"), []);
        compare(failureSpy.count, 1);
        verify(Calendar.lastError.includes("changed"));
        compare(Calendar.calendars.find(calendar => calendar.id === "work").color, "blue");
        compare(Calendar.add({ title: "After reload", date: "2026-10-06", calendarId: data.tag === "add" ? "berri" : "work" }), true);
        compare(TestIo.texts[path + ".bak"], current);
        compare(Format.readCalendar(TestIo.texts[path]).items.map(item => item.title).sort(), ["After reload", "External"]);
    }

    // Each replacement keeps exactly one previous version beside the calendar.
    function test_saves_keep_one_backup_before_each_replacement() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        startReading();
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), true);
        compare(TestIo.texts[berriPath + ".bak"], original);
        compare(TestIo.writes, [berriPath + ".bak", berriPath]);
        const previous = TestIo.texts[berriPath];
        compare(Calendar.remove(Items.itemKey("berri", "kept")), true);
        compare(TestIo.texts[berriPath + ".bak"], previous);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["New"]);
        compare(Object.keys(TestIo.texts).filter(path => path.endsWith(".bak")), [berriPath + ".bak"]);
        compare(Calendar.importFile(berriPath + ".bak"), "");
        compare(Calendar.lastError, "Not an .ics file");
    }

    // A disk change during the backup must survive and replace the shown content.
    function test_external_write_during_backup_refuses_the_save() {
        const original = savedText();
        const current = original.replace("SUMMARY:Kept", "SUMMARY:External");
        TestIo.texts[berriPath] = original;
        startReading();
        TestIo.afterWrite = function(path) {
            if (path === berriPath + ".bak") TestIo.texts[berriPath] = current;
        };
        compare(Calendar.add({ title: "Lost", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], current);
        compare(TestIo.texts[berriPath + ".bak"], original);
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["External"]);
        compare(Calendar.itemsOn("2026-10-06"), []);
        verify(Calendar.lastError.includes("File changed on disk"));
        TestIo.afterWrite = null;
        compare(Calendar.add({ title: "After reload", date: "2026-10-06" }), true);
        compare(TestIo.texts[berriPath + ".bak"], current);
    }

    // A backup failure stops the replacement and restores the shown items.
    function test_a_failed_backup_refuses_the_save() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        TestIo.texts[berriPath + ".bak"] = "Older backup";
        startReading();
        TestIo.deniedWrites[berriPath + ".bak"] = true;
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], original);
        compare(TestIo.texts[berriPath + ".bak"], "Older backup");
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["Kept"]);
        compare(Calendar.itemsOn("2026-10-06"), []);
        compare(failureSpy.count, 1);
        verify(Calendar.lastError.includes("backup"));
        TestIo.deniedWrites = ({});
        compare(Calendar.add({ title: "After retry", date: "2026-10-06" }), true);
        compare(TestIo.texts[berriPath + ".bak"], original);
    }

    // If the replacement fails after the backup, both files hold the previous text.
    function test_a_failed_replacement_keeps_the_file_and_backup() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        startReading();
        TestIo.deniedWrites[berriPath] = true;
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], original);
        compare(TestIo.texts[berriPath + ".bak"], original);
        compare(Calendar.itemsOn("2026-10-06"), []);
        TestIo.deniedWrites = ({});
        compare(Calendar.add({ title: "After retry", date: "2026-10-06" }), true);
        compare(Calendar.itemsOn("2026-10-06").map(item => item.title), ["After retry"]);
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

    // One timed event in a zone this machine does not know.
    function unknownZoneText(rule) {
        return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:test\r\nBEGIN:VEVENT\r\nUID:zoned\r\nDTSTAMP:20260101T000000Z\r\n" +
            "SUMMARY:Zoned\r\nDTSTART;TZID=Unknown/Zone:20261005T093000\r\n" + rule + "END:VEVENT\r\nEND:VCALENDAR\r\n";
    }

    // A write that cannot be prepared undoes the edit, reports it, and leaves the calendar usable.
    function test_edit_that_cannot_be_written_is_undone_and_later_saves_work_data() {
        return [{ tag: "end date on a repeat", rule: "RRULE:FREQ=DAILY\r\n", changes: { count: null, until: "2026-10-20" }, repeat: "daily" },
            { tag: "repeat added with an end date", rule: "", changes: { repeat: "daily", until: "2026-10-20" }, repeat: "none" }];
    }

    function test_edit_that_cannot_be_written_is_undone_and_later_saves_work(data) {
        const original = unknownZoneText(data.rule);
        const uid = Items.itemKey("berri", "zoned");
        TestIo.texts[berriPath] = original;
        startReading();
        compare(Calendar.update(uid, data.changes), false);
        compare(TestIo.writes.length, 0);
        compare(TestIo.texts[berriPath], original);
        compare(failureSpy.count, 1);
        verify(failureSpy.signalArguments[0][0].indexOf("Could not save berri: Cannot convert repeat end in an unknown time zone") === 0);
        compare(Calendar.lastError, failureSpy.signalArguments[0][0]);
        compare(Calendar.getItem(uid).repeat, data.repeat);
        compare(Calendar.getItem(uid).until, null);
        compare(Calendar.add({ title: "Later", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title).sort(), ["Later", "Zoned"]);
        compare(Calendar.update(uid, { title: "Renamed" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title).sort(), ["Later", "Renamed"]);
    }
}
