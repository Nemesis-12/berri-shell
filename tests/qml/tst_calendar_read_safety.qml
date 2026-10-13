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

    // An add must wait for the first read, then keep the items from that read.
    function test_add_before_the_first_read_keeps_all_old_items() {
        const original = savedText();
        TestIo.texts[berriPath] = original;
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), false);
        compare(TestIo.texts[berriPath], original);
        compare(TestIo.writes.length, 0);
        startReading();
        compare(Calendar.add({ title: "New", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title).sort(), ["Kept", "New"]);
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
        compare(Calendar.prepareCalendarWrite(Calendar.dir + "/unknown.ics"), null);
        TestIo.texts[berriPath] = savedText();
        startReading();
        compare(Calendar.prepareCalendarWrite(berriPath).previousText, savedText());
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
        compare(Calendar.calendars[0].error, "Could not read berri");
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

    // A missing file for a known calendar is a failed read, even with no cached items.
    function test_missing_known_calendar_is_never_empty_and_writable_data() {
        return [{ tag: "loaded local", kind: "local", loaded: true },
            { tag: "unread file", kind: "file", loaded: false },
            { tag: "loaded file", kind: "file", loaded: true },
            { tag: "restored local", kind: "restored", loaded: false }];
    }

    function test_missing_known_calendar_is_never_empty_and_writable(data) {
        if (data.kind === "restored") Calendar._loadState({ calendars: [{ id: "berri", file: "berri.ics" }] });
        const meta = data.kind === "file" ? Calendar._addCalendar("work", "file", "Work", "work.ics", "", "blue") : Calendar._calendars.berri;
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

    function test_a_missing_calendar_starts_empty_and_accepts_an_edit() {
        startReading();
        compare(Calendar.add({ title: "First", date: "2026-10-06" }), true);
        compare(Format.readCalendar(TestIo.texts[berriPath]).items.map(item => item.title), ["First"]);
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
}
