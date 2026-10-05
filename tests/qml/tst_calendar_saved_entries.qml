import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services

// Saved calendar entries from the settings file cannot write outside the calendar folder or start a download.
TestCase {
    id: tests
    name: "CalendarSavedEntries"

    function init() {
        TestIo.reset();
        Quickshell.detached = [];
        Calendar._calendars = ({});
        Calendar._order = [];
    }

    function entry(over) {
        return Object.assign({ id: "f-1ab", kind: "file", name: "x", color: "accent", file: "x.ics" }, over);
    }

    function test_unsafe_ids_and_files_are_not_loaded() {
        var bad = [
            entry({ id: "../escape", file: "x.ics" }),
            entry({ id: "f-2", file: "/etc/passwd.ics" }),
            entry({ id: "f-3", file: "sub/x.ics" }),
            entry({ id: "f-4", file: "..ics" }),
            entry({ id: "l-5", kind: "link", file: "subscriptions/../../x.ics", url: "https://example.test/a" }),
            entry({ id: "l-6", kind: "link", file: "other.ics", url: "https://example.test/a" }),
            entry({ id: "a/b", kind: "link", file: "subscriptions/a/b.ics", url: "https://example.test/a" })
        ];
        var good = entry({ id: "f-ok", file: "ok.ics" });
        Calendar._loadState({ calendars: bad.concat([good]) });
        compare(Calendar._order, ["berri", "f-ok"]);
        compare(Calendar._calendars["f-ok"].path, Calendar.dir + "/ok.ics");
        Calendar.removeCalendar("f-ok");
        compare(Quickshell.detached.length, 1);
        compare(Quickshell.detached[0], ["rm", "-f", Calendar.dir + "/ok.ics"]);
        compare(TestIo.writes.length, 0);
    }

    function test_rejected_feed_links_start_no_download() {
        var links = [
            entry({ id: "l-a", kind: "link", file: "subscriptions/l-a.ics", url: "file:///etc/passwd" }),
            entry({ id: "l-b", kind: "link", file: "subscriptions/l-b.ics", url: "http://example.test/a" }),
            entry({ id: "l-c", kind: "link", file: "subscriptions/l-c.ics", url: "" }),
            entry({ id: "l-d", kind: "link", file: "subscriptions/l-d.ics", url: "https://ok.example.test/a.ics" })
        ];
        Calendar._loadState({ calendars: links });
        Calendar._refreshLinks(false);
        // Only the valid link starts a download, into its own file name.
        compare(TestIo.downloads.length, 1);
        compare(TestIo.downloads[0].request.url, "https://ok.example.test/a.ics");
        compare(TestIo.downloads[0].command[4], Calendar.dir + "/subscriptions/l-d");
        compare(Calendar._calendars["l-a"].error, "Use an https:// or webcal:// link");
        compare(Calendar._calendars["l-a"].refreshing, false);
    }
}
