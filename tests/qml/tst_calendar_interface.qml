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

    // Refresh requests carry only link data, and failed refreshes keep the old items.
    function test_link_requests_and_results_keep_the_previous_items_on_error() {
        const request = { calendarId: "l-test", url: "https://example.test/feed", shownUrl: "webcal://example.test/feed", color: "blue", requestId: Calendar.nextSubscriptionRequest() };
        const doc = { name: "Feed", records: [{ uid: "one", kind: "event", title: "First", date: "2026-10-05" }] };
        const json = JSON.stringify(doc);
        TestIo.texts[Calendar.dir + "/subscriptions/l-test.json"] = json;
        Calendar.acceptSubscription(request, doc.name, doc, json, "");
        compare(Calendar.hasCalendar("l-test"), true);
        compare(Calendar.linkRefreshIds(false), ["l-test"]);
        compare(Calendar.linkRefreshIds(true), []);
        compare(Calendar.countLinkDuplicates(doc.records), 1);
        const refresh = Calendar.beginLinkRefresh("l-test", "Invalid link");
        compare(refresh, { shownUrl: request.url, url: request.url, calendarId: "l-test" });
        compare(Calendar.beginLinkRefresh("l-test", "Invalid link"), null);
        Calendar.acceptLinkRefresh("l-test", null, "", "Download failed");
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["First"]);
        compare(Calendar.calendars.find(calendar => calendar.id === "l-test").error, "Download failed");
        verify(Calendar.beginLinkRefresh("l-test", "Invalid link") !== null);
        const next = { name: "Feed", records: [{ uid: "two", kind: "event", title: "Second", date: "2026-10-06" }] };
        Calendar.acceptLinkRefresh("l-test", next, JSON.stringify(next), "");
        compare(Calendar.itemsOn("2026-10-05"), []);
        compare(Calendar.itemsOn("2026-10-06").map(item => item.title), ["Second"]);
        compare(Calendar.calendars.find(calendar => calendar.id === "l-test").error, "");
    }

}
