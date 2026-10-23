import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.tabs.calendar
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "CalendarInterface"

    SignalSpy { id: failedSaves; target: Calendar; signalName: "saveFailed" }

    // The form error tests go through the real tab: its Connections show the error and its form is the one the user sees.
    Component {
        id: tabComponent
        CalendarTab { width: 868; height: 544; selectedDate: new Date(2026, 9, 5) }
    }

    function formOf(item) {
        if (item instanceof CalendarDetailsForm) return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = formOf(item.children[i]);
            if (found) return found;
        }
        return null;
    }

    // Set up an unread local calendar without starting saved-state loading.
    function init() {
        TestIo.reset();
        failedSaves.clear();
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
        TestIo.texts[Calendar.defaultPath] = text;
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

    // An unknown id is not writable. It does not throw.
    function test_unknown_calendar_is_not_writable() {
        compare(Calendar.canWriteCalendar("missing"), false);
        compare(failedSaves.count, 0);
    }
    // A failed read stays refused while the re-read fails, and the error is reported.
    function test_failed_read_then_failed_reread_refuses_writes() {
        Calendar.acceptCalendarRead(Calendar.defaultPath, "", true);
        TestIo.deniedReads[Calendar.defaultPath] = true;
        compare(Calendar.canWriteCalendar("berri"), false);
        compare(failedSaves.count, 1);
        compare(failedSaves.signalArguments[0][0], "Could not read berri");
        compare(Calendar.lastError, "Could not read berri");
    }
    // A good re-read after failed ones allows writes again.
    function test_failed_reread_then_good_reread_allows_writes() {
        Calendar.acceptCalendarRead(Calendar.defaultPath, "", true);
        TestIo.deniedReads[Calendar.defaultPath] = true;
        compare(Calendar.canWriteCalendar("berri"), false);
        TestIo.deniedReads = ({});
        TestIo.texts[Calendar.defaultPath] = Format.writeCalendar(Format.emptyCalendar());
        compare(Calendar.canWriteCalendar("berri"), true);
        compare(failedSaves.count, 1);
    }
    // A failed write puts the old document back and reports the error.
    function test_failed_write_restores_the_old_document() {
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        Calendar._calendars.berri.document.items.push(Items.makeItem({ uid: "lost", title: "Lost", date: "2026-10-05" }));
        const saved = Calendar.acceptCalendarWrite(Calendar.defaultPath, { saved: false, text: text, error: "Disk full" }, null);
        compare(saved, false);
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["Kept"]);
        compare(Calendar.lastError, "Disk full");
        compare(failedSaves.count, 1);
        compare(failedSaves.signalArguments[0][0], "Disk full");
    }

    function test_failed_save_keeps_the_form_open_with_its_draft() {
        const tab = createTemporaryObject(tabComponent, tests);
        verify(tab !== null);
        const form = formOf(tab);
        verify(form !== null);
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
        TestIo.texts[Calendar.defaultPath] = text;
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        TestIo.failWrite = true;
        form.openNew(new Date(2026, 9, 6));
        form.title = "Draft to keep";
        form.save();
        compare(form.shown, true);
        compare([form.title, form.date], ["Draft to keep", "2026-10-06"]);
        verify(tab.saveError !== "");
        compare(tab.saveError, Calendar.lastError);
        compare(Calendar.itemsOn("2026-10-06"), []);
    }

    function test_failed_remove_keeps_the_form_open_and_shows_the_error() {
        const tab = createTemporaryObject(tabComponent, tests);
        verify(tab !== null);
        const form = formOf(tab);
        verify(form !== null);
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
        TestIo.texts[Calendar.defaultPath] = text;
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        TestIo.failWrite = true;
        form.openEdit(Items.itemKey("berri", "kept"), "2026-10-05", "2026-10-05");
        form.remove();
        compare(form.shown, true);
        verify(tab.saveError !== "");
        compare(tab.saveError, Calendar.lastError);
        compare(Calendar.itemsOn("2026-10-05").map(item => item.title), ["Kept"]);
    }

    function test_missing_item_save_keeps_the_form_open_and_shows_the_error() {
        const tab = createTemporaryObject(tabComponent, tests);
        verify(tab !== null);
        const form = formOf(tab);
        verify(form !== null);
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "kept", title: "Kept", date: "2026-10-05" })] }));
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        form.openEdit(Items.itemKey("berri", "kept"), "2026-10-05", "2026-10-05");
        Calendar.acceptCalendarRead(Calendar.defaultPath, Format.writeCalendar(Format.emptyCalendar()), false);
        form.title = "Edited after reload";
        form.save();
        compare(form.shown, true);
        verify(tab.saveError !== "");
        compare(tab.saveError, Calendar.lastError);
    }

    function test_failed_repeat_move_restores_the_series_and_drops_the_new_item() {
        const text = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [Items.makeItem({ uid: "repeat", title: "Repeat", date: "2026-10-01", time: "09:00",
                end: "10:00", repeat: "daily", doneDates: ["2026-10-08"] })] }));
        TestIo.texts[Calendar.defaultPath] = text;
        Calendar.acceptCalendarRead(Calendar.defaultPath, text, false);
        TestIo.failWrite = true;
        const uid = Items.itemKey("berri", "repeat");
        compare(Calendar.move(uid, "2026-10-08", "2026-10-09", {}), false);
        compare(Calendar.getItem(uid).exdates, []);
        compare(Calendar.itemsOn("2026-10-08").map(item => item.uid), [uid]);
        compare(Calendar.itemsOn("2026-10-09").map(item => item.uid), [uid]);
    }

    function test_read_only_details_show_the_clicked_changed_occurrence() {
        const feed = Calendar._newMeta("feed", "link", "Feed", "feed.ics", "blue");
        feed.records = [Items.storedItem({ uid: "series", title: "Master", date: "2026-09-01", time: "09:00",
            end: "10:00", repeat: "daily", count: 4, changedOccurrences: [{ from: "2026-09-02", cancelled: false,
                title: "Changed", date: "2026-10-09", time: "15:00", end: "16:00", endDate: null }] })];
        Calendar._calendars = { feed: feed };
        Calendar._order = ["feed"];
        Calendar._rebuild();
        const form = formOf(createTemporaryObject(tabComponent, tests));
        verify(form !== null);
        form.openEdit(Items.itemKey("feed", "series"), "2026-09-02", "2026-10-09");
        compare([form.title, form.date, form.time, form.end], ["Changed", "2026-10-09", "15:00", "16:00"]);
    }

    // On 2026-10-09 this series shows its own occurrence (09:00) and the one that moved there from 2026-10-08 (15:00).
    function test_read_only_details_pick_the_occurrence_by_its_date_when_two_share_a_day() {
        const feed = Calendar._newMeta("feed", "link", "Feed", "feed.ics", "blue");
        feed.records = [Items.storedItem({ uid: "series", title: "Master", date: "2026-10-01", time: "09:00",
            end: "10:00", repeat: "daily", count: 20, changedOccurrences: [{ from: "2026-10-08", cancelled: false,
                title: "Changed", date: "2026-10-09", time: "15:00", end: "16:00", endDate: null }] })];
        Calendar._calendars = { feed: feed };
        Calendar._order = ["feed"];
        Calendar._rebuild();
        const form = formOf(createTemporaryObject(tabComponent, tests));
        verify(form !== null);
        const uid = Items.itemKey("feed", "series");
        form.openEdit(uid, "2026-10-08", "2026-10-09");
        compare([form.title, form.time, form.end], ["Changed", "15:00", "16:00"]);
        form.openEdit(uid, "2026-10-09", "2026-10-09");
        compare([form.title, form.time, form.end], ["Master", "09:00", "10:00"]);
    }

}
