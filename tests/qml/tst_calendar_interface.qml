import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "CalendarInterface"

    // Set up an unread local calendar without starting saved-state loading.
    function init() {
        TestIo.reset();
        const files = Calendar.children.find(child => child instanceof CalendarFiles);
        files.paths = [];
        Calendar.ready = false;
        Calendar._stateRead = false;
        Calendar._calendars = { berri: Calendar._newMeta("berri", "local", "berri", "berri.ics", "") };
        Calendar._order = ["berri"];
        Calendar._rebuild();
    }

    // File helpers receive write text while the service keeps the document.
    function test_read_result_prepares_the_same_document_for_writing() {
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["Kept"]);
        const write = Calendar.prepareCalendarWrite(Calendar.defaultPath);
        compare(write.previousText, text);
        compare(Format.readCalendar(write.nextText).items.map(item => item.title), ["Kept"]);
        compare(write.failurePrefix, "Could not save berri");
        compare(write.document, undefined);
    }
    // Import planning detects existing files and counts local duplicates before a write.
    function test_import_plan_and_result_keep_duplicate_and_identity_rules() {
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        const prepared = Calendar.prepareCalendarImport("/outside/trips.ics", text);
        compare(prepared.path, Calendar.dir + "/trips.ics");
        compare(prepared.duplicates, 1);
        TestIo.texts[prepared.path] = text;
        const id = Calendar.acceptCalendarImport(prepared, text, "blue");
        compare(Calendar.calendars.map(calendar => calendar.id), ["berri", id]);
        compare(Calendar.lastImportDuplicates, 1);
        compare(Calendar.prepareCalendarImport("/outside/other.ics", text).existingId, id);
    }

}
