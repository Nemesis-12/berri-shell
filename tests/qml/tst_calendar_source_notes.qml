import QtQuick
import QtTest
import Quickshell.Io
import qs.common
import qs.services
import qs.tabs.calendar
import "../logic/CalendarFormat.js" as Format

TestCase {
    id: tests
    name: "CalendarSourceNotes"
    width: 900
    height: 600
    visible: true
    when: windowShown

    // The isolated runner can set this path to capture the actual rendered rows.
    property string capturePath: ""
    Component { id: sourceView; CalendarSourcesView { width: 434; height: 544 } }

    // Gives the actual view a normal source, a source note and a real download failure.
    function init() {
        TestIo.reset();
        var record = { uid: "repeat", title: "Repeat", date: "2026-10-05",
            raw: ["RDATE:20261012T090000", "EXRULE:FREQ=WEEKLY;BYDAY=MO"] };
        Calendar._calendars = {
            normal: { id: "normal", name: "A normal file", kind: "file", color: "blue", file: "normal.ics",
                document: Format.emptyCalendar(), hidden: false },
            note: { id: "note", name: "B repeat note", kind: "link", color: "blue",
                url: "https://example.test/note", records: [record], hidden: false, updatedAt: 1 },
            failed: { id: "failed", name: "C failed download", kind: "link", color: "blue",
                url: "https://example.test/failed", records: [record], hidden: false, updatedAt: 1, error: "Download failed" }
        };
        Calendar._order = ["normal", "note", "failed"];
        Calendar.parserError = "";
        Calendar._rebuild();
    }

    // Finds loaded source delegates and text using the complete view's item tree.
    function findItem(parent, matches) {
        if (matches(parent)) return parent;
        for (var i = 0; i < parent.children.length; i++) {
            var found = findItem(parent.children[i], matches);
            if (found) return found;
        }
        return null;
    }

    function test_notes_use_normal_text_and_real_failures_keep_their_error() {
        var view = createTemporaryObject(sourceView, tests);
        verify(view !== null);
        wait(Theme.stateMs + Theme.listMs + 50);
        var normal = findItem(view, item => item instanceof CalendarSourceRow && item.calId === "normal");
        var note = findItem(view, item => item instanceof CalendarSourceRow && item.calId === "note");
        var failed = findItem(view, item => item instanceof CalendarSourceRow && item.calId === "failed");
        verify(normal !== null && note !== null && failed !== null);
        waitForRendering(view);
        if (capturePath !== "") {
            grabImage(view).save(capturePath + "/sources.png");
        }
        compare(normal.sourceLine, "0 items");
        compare(failed.sourceLine, "Download failed");
        var failedText = findItem(failed, item => item instanceof MonoText && item.text === "DOWNLOAD FAILED");
        compare(failedText.color, view.redColor);
        compare(note.failure, "");
        compare(note.sourceLine, "RDATE and EXRULE are not supported");
        var noteText = findItem(note, item => item instanceof MonoText && item.text === "RDATE AND EXRULE ARE NOT SUPPORTED");
        compare(noteText.color, Theme.dim);
    }
}
