import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.tabs.calendar
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "CalendarComponents"
    width: 900
    height: 600

    Component {
        id: tabComponent
        CalendarTab {
            width: 868
            height: 544
            selectedDate: new Date(2026, 9, 5)
        }
    }

    // Nonempty calendars force the source, day and month delegates to load.
    function init() {
        TestIo.reset();
        var document = Format.emptyCalendar();
        document.items = [Items.makeItem({ uid: "one", title: "Meeting", date: "2026-10-05", time: "09:00" })];
        Calendar._calendars = {
            berri: { id: "berri", name: "berri", kind: "local", color: "accent", hidden: false,
                path: Calendar.defaultPath, file: "berri.ics", document: document, text: Format.writeCalendar(document) },
            feed: { id: "feed", name: "Feed", kind: "link", color: "blue", hidden: false,
                path: Calendar.dir + "/subscriptions/feed.ics", file: "subscriptions/feed.ics",
                url: "https://example.test/feed", records: [], colorOverrides: {} }
        };
        Calendar._order = ["berri", "feed"];
        Calendar.lastError = "";
        Calendar._rebuild();
    }

    function test_tab_loads_and_service_signals_update_the_view() {
        var tab = createTemporaryObject(tabComponent, tests);
        verify(tab !== null);
        tab.showMonth(2026, 9);
        Calendar.saveFailed("Permission denied");
        compare(tab.saveError, "Permission denied");
        Calendar.revision++;
        compare(tab.saveError, "");
        tab.toggleCalendars();
        compare(tab.showCalendars, true);
        tab.addOn(new Date(2026, 9, 6));
        compare(tab.selectedDate.getDate(), 6);
        wait(1);
    }
}
