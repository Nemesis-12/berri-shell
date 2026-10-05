import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.tabs.calendar
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items

TestCase {
    id: tests
    name: "CalendarDays"
    width: 900
    height: 600
    visible: true
    when: windowShown

    Component {
        id: tabComponent
        CalendarTab {
            width: 868
            height: 544
            selectedDate: new Date(2026, 9, 5)
        }
    }

    SignalSpy { id: clicked; signalName: "itemClicked" }

    function init() {
        TestIo.reset();
        var document = Format.emptyCalendar();
        document.items = [Items.makeItem({ uid: "one", title: "Meeting", date: "2026-10-05", time: "09:00" })];
        Calendar._calendars = {
            berri: { id: "berri", name: "berri", kind: "local", color: "accent", hidden: false,
                path: Calendar.defaultPath, file: "berri.ics", document: document, text: Format.writeCalendar(document) }
        };
        Calendar._order = ["berri"];
        Calendar.lastError = "";
        Calendar._rebuild();
    }

    // Opens a tab on October 2026 and returns it with the scene point of a spot in a day cell.
    function openOctober() {
        var tab = createTemporaryObject(tabComponent, tests);
        tab.showMonth(2026, 9);
        wait(300);
        return tab;
    }

    // Point in tab coordinates: dx, dy from the top-left corner of the cell of `day`.
    function inCell(tab, day, dx, dy) {
        var corner = tab.frontGrid.cellOriginOnScene(day);
        return tab.mapFromItem(null, corner.x + dx, corner.y + dy);
    }

    function test_a_chip_click_opens_its_item() {
        var tab = openOctober();
        clicked.target = tab;
        clicked.clear();
        var p = inCell(tab, new Date(2026, 9, 5), 30, 16 + 3 + 6);
        mouseClick(tab, p.x, p.y);
        compare(clicked.count, 1);
        compare(clicked.signalArguments[0][0], Items.itemKey("berri", "one"));
    }

    function test_a_blank_cell_click_selects_the_day() {
        var tab = openOctober();
        var p = inCell(tab, new Date(2026, 9, 7), 30, 40);
        mouseClick(tab, p.x, p.y);
        compare(tab.selectedDate.getDate(), 7);
    }

    function test_a_chip_drag_starts_after_6_pixels_but_not_after_4() {
        var tab = openOctober();
        var p = inCell(tab, new Date(2026, 9, 5), 30, 16 + 3 + 6);
        mousePress(tab, p.x, p.y);
        mouseMove(tab, p.x + 4, p.y, 0, Qt.LeftButton);
        compare(tab.dragging, false);
        mouseMove(tab, p.x + 6, p.y, 0, Qt.LeftButton);
        compare(tab.dragging, true);
        mouseRelease(tab, p.x + 6, p.y);
    }

    function test_reopening_on_a_later_day_selects_the_current_day() {
        var tab = openOctober();
        Clock.minute = new Date(2026, 9, 5, 12, 0);
        tab.panelOpen = true;
        tab.panelOpen = false;
        tab.selectedDate = new Date(2026, 9, 5);
        Clock.minute = new Date(2026, 9, 6, 0, 1);
        tab.panelOpen = true;
        compare(tab.selectedDate.getDate(), 6);
    }

    function test_reopening_on_the_same_day_keeps_the_picked_day() {
        var tab = openOctober();
        Clock.minute = new Date(2026, 9, 5, 12, 0);
        tab.panelOpen = false;
        tab.selectedDate = new Date(2026, 9, 20);
        Clock.minute = new Date(2026, 9, 5, 18, 0);
        tab.panelOpen = true;
        compare(tab.selectedDate.getDate(), 20);
    }
}
