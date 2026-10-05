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
    name: "CalendarCache"
    width: 900
    height: 600
    visible: true
    when: windowShown

    readonly property string feed: "https://example.test/feed"

    Component {
        id: tabComponent
        CalendarTab {
            width: 868
            height: 544
            selectedDate: new Date(2026, 9, 5)
        }
    }

    function record(title) { return { uid: title, kind: "event", title: title, date: "2026-10-05" }; }

    // Starts with the local calendar and one subscription that shows `records`.
    function init() {
        TestIo.reset();
        Quickshell.detached = [];
        Calendar.lastError = "";
        Calendar._calendars = { berri: Calendar._newMeta("berri", "local", "berri", "berri.ics", "") };
        Calendar._order = ["berri"];
        Calendar._rebuild();
        Calendar.subscribe(feed, "blue");
        finishDownload([record("One"), record("Two")]);
    }

    function finishDownload(records) {
        const download = TestIo.downloads[TestIo.downloads.length - 1];
        TestIo.texts["/feed.json"] = JSON.stringify({ name: "Feed", records: records });
        download.stdout.text = "/feed.json";
        download.exited(0, 0);
    }

    function feedId() { return Calendar._order.filter(id => id !== "berri")[0]; }

    function test_an_unchanged_feed_refresh_builds_no_month() {
        const october = Calendar.itemsInMonth(2026, 10);
        const builds = Calendar._months.builds;
        const before = Calendar.revision;
        Calendar.refresh(feedId());
        finishDownload([record("One"), record("Two")]);
        Calendar.itemsInMonth(2026, 10);
        verify(Calendar.revision > before);
        compare(Calendar._months.builds, builds);
        verify(Calendar.itemsInMonth(2026, 10) === october);
    }

    function test_a_changed_feed_refresh_builds_the_month_again() {
        Calendar.itemsInMonth(2026, 10);
        Calendar.refresh(feedId());
        finishDownload([record("One"), record("Three")]);
        // A changed feed starts a new cache, so the count starts again.
        compare(Calendar.itemsInMonth(2026, 10)["2026-10-05"].map(item => item.title).sort(), ["One", "Three"]);
        compare(Calendar._months.builds, 1);
    }

    function test_a_revision_with_a_hidden_tab_builds_no_month() {
        const tab = createTemporaryObject(tabComponent, tests, { visible: false });
        Calendar.refresh(feedId());
        finishDownload([record("One"), record("Three")]);
        compare(Calendar._months.builds, 0);
        tab.visible = true;
        // Only the front page builds: the month before, this month and the month after.
        compare(Calendar._months.builds, 3);
    }

    function test_a_revision_builds_only_the_front_page_months() {
        const tab = createTemporaryObject(tabComponent, tests);
        tab.showMonth(2026, 9);
        wait(400);
        Calendar.refresh(feedId());
        finishDownload([record("One"), record("Three")]);
        compare(Calendar._months.builds, 3);
    }

    // Two pages three months apart both show during a page change. A revision with the same
    // months must read six months from the cache and build none.
    function test_two_shown_pages_three_months_apart_fit_the_cache() {
        const tab = createTemporaryObject(tabComponent, tests);
        tab.showMonth(2026, 0);
        wait(400);
        tab.showMonth(2026, 3);
        tab.progress = 0.5;
        const builds = Calendar._months.builds;
        Calendar.refresh(feedId());
        finishDownload([record("One"), record("Two")]);
        Calendar.refresh(feedId());
        finishDownload([record("One"), record("Two")]);
        compare(Calendar._months.builds, builds);
    }
}
