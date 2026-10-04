import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.tabs.calendar
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "Calendar"
    width: 900
    height: 600

    // Build one stored item for a service action.
    function item(fields) { return Items.makeItem(Object.assign({ uid: "edited", title: "Before", date: "2026-10-05" }, fields)); }
    // Build calendar metadata for the stored items.
    function calendar(items, fields) {
        return Object.assign({ id: "berri", name: "berri", kind: "local", color: "accent", hidden: false, document: { items: items } }, fields || {});
    }
    // Seed the actual service while disk and network access stay in memory.
    function service(items, extras) {
        TestIo.reset();
        failureSpy.clear();
        var local = calendar(items, { path: Calendar.defaultPath, file: "berri.ics" });
        local.document = Object.assign(Format.emptyCalendar(), { items: items });
        local.text = Format.writeCalendar(local.document);
        var list = [local].concat(extras || []);
        var stored = {};
        list.forEach(function (entry) { stored[entry.id] = entry; });
        Calendar.ready = false;
        Calendar._stateRead = false;
        Calendar.lastError = "";
        Calendar._calendars = stored;
        Calendar._order = list.map(function (entry) { return entry.id; });
        Calendar._rebuild();
        return Calendar;
    }
    // Copy Qt values for comparisons with literal test results.
    function plain(value) { return JSON.parse(JSON.stringify(value)); }

    // The service save updates the edited month and retains the other month objects.
    function test_the_service_save_updates_the_edited_month_and_retains_the_other_month_objects() {
        const shell = service([item({})]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        compare(shell.update(Items.itemKey("berri", "edited"), { title: "Saved" }), true);
        same(shell.itemsInMonth(2026, 9), september);
        same(shell.itemsInMonth(2026, 11), november);
        different(shell.itemsInMonth(2026, 10), october);
        compare(shell.itemsOn("2026-10-05")[0].title, "Saved");
        compare(Format.readCalendar(TestIo.texts[Calendar.defaultPath]).items[0].title, "Saved");
    }

    // An unbounded repeat edit updates every cached occurrence month but keeps earlier months.
    function test_an_unbounded_repeat_edit_updates_every_cached_occurrence_month_but_keeps_earlier_months() {
        const shell = service([item({ date: "2026-10-05", repeat: "monthly" })]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        const future = shell.itemsInMonth(2036, 10);
        compare(shell.update(Items.itemKey("berri", "edited"), { title: "Series" }), true);
        same(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        different(shell.itemsInMonth(2036, 10), future);
        compare(shell.itemsOn("2026-10-05")[0].title, "Series");
        compare(shell.itemsOn("2036-10-05")[0].title, "Series");
    }

    // A repeat rule change clears old and new occurrence months and keeps gaps cached.
    function test_a_repeat_rule_change_clears_old_and_new_occurrence_months_and_keeps_gaps_cached() {
        const shell = service([item({ date: "2026-01-05", repeat: "monthly", count: 2 })]);
        const february = shell.itemsInMonth(2026, 2);
        const march = shell.itemsInMonth(2026, 3);
        const nextYear = shell.itemsInMonth(2027, 1);
        compare(shell.update(Items.itemKey("berri", "edited"), { repeat: "yearly" }), true);
        different(shell.itemsInMonth(2026, 2), february);
        compare(plain(shell.itemsInMonth(2026, 2)), {});
        same(shell.itemsInMonth(2026, 3), march);
        different(shell.itemsInMonth(2027, 1), nextYear);
        compare(shell.itemsOn("2027-01-05")[0].title, "Before");
        compare(shell.update(Items.itemKey("berri", "edited"), { repeat: "none" }), true);
        compare(plain(shell.itemsInMonth(2027, 1)), {});
        compare(shell.itemsOn("2026-01-05")[0].recurring, false);
    }

    // Moving a single item clears its old and new months and keeps the month between them.
    function test_moving_a_single_item_clears_its_old_and_new_months_and_keeps_the_month_between_them() {
        const shell = service([item({ date: "2026-09-05" })]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        compare(shell.move(Items.itemKey("berri", "edited"), "2026-09-05", "2026-11-05", {}), true);
        different(shell.itemsInMonth(2026, 9), september);
        compare(plain(shell.itemsInMonth(2026, 9)), {});
        same(shell.itemsInMonth(2026, 10), october);
        different(shell.itemsInMonth(2026, 11), november);
        compare(shell.itemsOn("2026-11-05")[0].occurrenceDate, "2026-11-05");
    }

    // Moving one repeat occurrence updates both spans and keeps the remaining series cached.
    function test_moving_one_repeat_occurrence_updates_both_spans_and_keeps_the_remaining_series_cached() {
        const shell = service([item({ date: "2026-09-30", endDate: "2026-10-02", repeat: "monthly" })]);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        const december = shell.itemsInMonth(2026, 12);
        compare(shell.move(Items.itemKey("berri", "edited"), "2026-09-30", "2026-12-30", {}), true);
        different(shell.itemsInMonth(2026, 10), october);
        compare(plain(shell.itemsOn("2026-10-01")), []);
        compare(shell.itemsOn("2026-10-30")[0].recurring, true);
        same(shell.itemsInMonth(2026, 11), november);
        compare(november["2026-11-01"][0].occurrenceDate, "2026-10-30");
        different(shell.itemsInMonth(2026, 12), december);
        compare(plain(shell.itemsOn("2026-12-30").map(o => o.recurring)), [true, false]);
        compare(shell.itemsOn("2027-01-01").some(o => o.occurrenceDate === "2026-12-30" && !o.recurring), true);
    }

    // A repeat delete clears its occurrence months, including a final multi-day span.
    function test_a_repeat_delete_clears_its_occurrence_months_including_a_final_multi_day_span() {
        const shell = service([item({ date: "2026-09-29", endDate: "2026-10-02", repeat: "daily", until: "2026-09-30" })]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        compare(shell.remove(Items.itemKey("berri", "edited")), true);
        different(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        same(shell.itemsInMonth(2026, 11), november);
        compare(plain(shell.itemsInMonth(2026, 10)), {});
        compare(shell.add({ date: "2026-10-08", title: "Added" }), true);
        compare(shell.itemsOn("2026-10-08")[0].title, "Added");
        same(shell.itemsInMonth(2026, 11), november);
    }

    // Ticking or deleting one repeat occurrence keeps its other occurrence months cached.
    function test_ticking_or_deleting_one_repeat_occurrence_keeps_its_other_occurrence_months_cached() {
        const shell = service([item({ repeat: "monthly" })]);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        const december = shell.itemsInMonth(2026, 12);
        const uid = Items.itemKey("berri", "edited");
        compare(shell.setDone(uid, true, "2026-10-05"), true);
        different(shell.itemsInMonth(2026, 10), october);
        compare(shell.itemsOn("2026-10-05")[0].done, true);
        same(shell.itemsInMonth(2026, 11), november);
        compare(november["2026-11-05"][0].done, false);
        compare(shell.remove(uid, "2026-10-05"), true);
        compare(plain(shell.itemsOn("2026-10-05")), []);
        same(shell.itemsInMonth(2026, 11), november);
        same(shell.itemsInMonth(2026, 12), december);
    }

    // COUNT and a skipped monthly date limit the months affected by a series edit.
    function test_count_and_a_skipped_monthly_date_limit_the_months_affected_by_a_series_edit() {
        const shell = service([item({ date: "2026-01-31", repeat: "monthly", count: 2 })]);
        const february = shell.itemsInMonth(2026, 2);
        const march = shell.itemsInMonth(2026, 3);
        const april = shell.itemsInMonth(2026, 4);
        compare(shell.update(Items.itemKey("berri", "edited"), { title: "Limited" }), true);
        same(shell.itemsInMonth(2026, 2), february);
        different(shell.itemsInMonth(2026, 3), march);
        compare(shell.itemsOn("2026-03-31")[0].title, "Limited");
        same(shell.itemsInMonth(2026, 4), april);
        compare(plain(april), {});
    }

    // Shortening UNTIL clears a final span without rebuilding earlier unchanged months.
    function test_shortening_until_clears_a_final_span_without_rebuilding_earlier_unchanged_months() {
        const shell = service([item({ date: "2026-09-29", endDate: "2026-10-02", repeat: "daily", until: "2026-09-30" })]);
        const august = shell.itemsInMonth(2026, 8);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        compare(shell.update(Items.itemKey("berri", "edited"), { until: "2026-09-29" }), true);
        same(shell.itemsInMonth(2026, 8), august);
        different(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        compare(plain(shell.itemsOn("2026-10-02").map(o => o.occurrenceDate)), ["2026-09-29"]);
        compare(plain(shell.itemsOn("2026-10-03")), []);
    }

    // A link item's own color changes the kept duplicate in every affected month.
    function test_a_link_item_s_own_color_changes_the_kept_duplicate_in_every_affected_month() {
        const repeated = item({ repeat: "monthly" });
        const feed = { id: "feed", name: "Feed", kind: "link", color: "blue", hidden: false,
            records: [plain(repeated)], colorOverrides: {} };
        const shell = service([repeated], [feed]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        compare(october["2026-10-05"][0].calendarId, "berri");
        compare(shell.setItemColor(Items.itemKey("feed", "edited"), "red"), true);
        same(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        different(shell.itemsInMonth(2026, 11), november);
        const shown = shell.itemsOn("2026-11-05");
        compare(shown.length, 1);
        compare(shown[0].calendarId, "feed");
        compare(shown[0].color, "red");
        compare(plain(shown[0].alsoInIds), ["berri"]);
        compare(shell.setItemColor(Items.itemKey("feed", "edited"), null), true);
        compare(shell.itemsOn("2026-11-05")[0].calendarId, "berri");
    }

    // A failed item save restores the item and retains unchanged cached views.
    function test_a_failed_item_save_restores_the_item_and_retains_unchanged_cached_views() {
        const shell = service([item({ repeat: "monthly" })]);
        const october = shell.itemsInMonth(2026, 10);
        const november = shell.itemsInMonth(2026, 11);
        TestIo.failWrite = true;
        compare(shell.update(Items.itemKey("berri", "edited"), { date: "2027-01-05", title: "Lost" }), false);
        same(shell.itemsInMonth(2026, 10), october);
        same(shell.itemsInMonth(2026, 11), november);
        compare(shell.getItem(Items.itemKey("berri", "edited")).title, "Before");
        compare(failureSpy.signalArguments[0][0], "Could not save berri: Permission denied");
        compare(shell.lastError, failureSpy.signalArguments[0][0]);
    }

    // A file import keeps the full rebuild and exposes the imported month.
    function test_a_file_import_keeps_the_full_rebuild_and_exposes_the_imported_month() {
        const shell = service([item({})]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        TestIo.texts["/outside/copied.ics"] = Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [item({ uid: "imported", date: "2026-09-12", title: "Imported" })] }));
        const id = shell.importFile("/outside/copied.ics", "blue");
        different(id, "");
        different(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        compare(shell.itemsOn("2026-09-12")[0].title, "Imported");
        compare(shell.itemsOn("2026-09-12")[0].calendarId, id);
    }

    // Calendar-wide color and visibility settings keep the full rebuild.
    function test_calendar_wide_color_and_visibility_settings_keep_the_full_rebuild() {
        const shell = service([item({})]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        shell.setCalendarColor("berri", "green");
        different(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        compare(shell.itemsOn("2026-10-05")[0].color, "green");
        const colored = shell.itemsInMonth(2026, 10);
        shell.setCalendarHidden("berri", true);
        different(shell.itemsInMonth(2026, 10), colored);
        compare(plain(shell.itemsOn("2026-10-05")), []);
        shell.setCalendarHidden("berri", false);
        compare(shell.itemsOn("2026-10-05")[0].color, "green");
    }

    // Moving a whole repeat series to a new start clears its old and new ranges.
    function test_moving_a_whole_repeat_series_to_a_new_start_clears_its_old_and_new_ranges() {
        const shell = service([item({ date: "2026-09-05", repeat: "monthly", count: 2 })]);
        const september = shell.itemsInMonth(2026, 9);
        const december = shell.itemsInMonth(2026, 12);
        const february = shell.itemsInMonth(2027, 2);
        compare(shell.update(Items.itemKey("berri", "edited"), { date: "2026-12-05" }), true);
        different(shell.itemsInMonth(2026, 9), september);
        compare(plain(shell.itemsInMonth(2026, 9)), {});
        different(shell.itemsInMonth(2026, 12), december);
        compare(shell.itemsOn("2026-12-05")[0].title, "Before");
        same(shell.itemsInMonth(2027, 2), february);
        compare(plain(shell.itemsOn("2026-10-05")), []);
        compare(shell.itemsOn("2027-01-05")[0].title, "Before");
    }

    // Item edits update reminder inputs and leave other calendars' month inputs shared.
    function test_item_edits_update_reminder_inputs_and_leave_other_calendars_month_inputs_shared() {
        const second = calendar([item({ uid: "second", kind: "reminder", title: "Second" })],
            { id: "second", name: "Second", kind: "file", path: Calendar.dir + "/second.ics", file: "second.ics" });
        const shell = service([item({ kind: "reminder", title: "First" })], [second]);
        const source = shell._months.projection.sources[1];
        const row = shell._months.projection.calendars[1];
        compare(shell.update(Items.itemKey("berri", "edited"), { title: "Changed", time: "10:00" }), true);
        compare(plain(shell.allItems().map(it => [it.title, it.time])), [["Changed", "10:00"], ["Second", "09:00"]]);
        same(shell._months.projection.sources[1], source);
        same(shell._months.projection.calendars[1], row);
        compare(shell.add({ kind: "reminder", date: "2026-10-08", title: "New" }), true);
        compare(shell._months.projection.calendars[0].itemCount, 2);
        compare(shell.allItems().length, 3);
    }

    // Outside file changes and bulk item colors clear all month caches.
    function test_outside_file_changes_and_bulk_item_colors_clear_all_month_caches() {
        const second = calendar([item({ color: "red" })],
            { id: "second", name: "Second", kind: "file", path: Calendar.dir + "/second.ics", file: "second.ics" });
        second.document = Object.assign(Format.emptyCalendar(), { items: second.document.items });
        second.text = Format.writeCalendar(second.document);
        const shell = service([], [second]);
        const september = shell.itemsInMonth(2026, 9);
        const october = shell.itemsInMonth(2026, 10);
        compare(shell.applyColorToCalendar("second", "blue"), true);
        different(shell.itemsInMonth(2026, 9), september);
        different(shell.itemsInMonth(2026, 10), october);
        compare(shell.itemsOn("2026-10-05")[0].color, "blue");
        const colored = shell.itemsInMonth(2026, 10);
        calendarFiles().read(Calendar.dir + "/second.ics", Format.writeCalendar(Object.assign(Format.emptyCalendar(), {
            items: [item({ date: "2026-10-05", title: "Outside" })] })), false);
        different(shell.itemsInMonth(2026, 10), colored);
        compare(shell.itemsOn("2026-10-05")[0].title, "Outside");
    }

    // Deliver outside file changes through the actual service connection.
    function calendarFiles() {
        return Calendar.children.find(function (child) { return child instanceof CalendarFiles; });
    }

    SignalSpy { id: failureSpy; target: Calendar; signalName: "saveFailed" }
    // Check object identity when a cache must keep the same month.
    function same(actual, expected) { verify(actual === expected); }
    function different(actual, expected) { verify(actual !== expected); }
}
