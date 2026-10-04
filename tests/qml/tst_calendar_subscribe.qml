import QtQuick
import QtTest
import Quickshell.Io
import qs.services
import qs.tabs.calendar
import "../logic/CalendarQueries.js" as Queries

TestCase {
    id: tests
    name: "CalendarSubscribe"
    width: 900
    height: 600

    Component { id: sourceView; CalendarSourcesView { width: 434; height: 544 } }
    SignalSpy { id: results; target: Calendar; signalName: "subscribed" }

    // Reset the actual service without loading saved settings.
    function init() {
        TestIo.reset();
        results.clear();
        Calendar._nextSubscription = 0;
        Calendar._calendars = ({});
        Calendar._order = [];
        Calendar.lastError = "";
        Calendar.parserError = "";
        Calendar._rebuild();
    }

    // Find the actual link box without adding test properties to the component.
    function linkBox(parent) {
        if (parent instanceof CalendarLinkBox) return parent;
        for (var i = 0; i < parent.children.length; i++) {
            var found = linkBox(parent.children[i]);
            if (found) return found;
        }
        return null;
    }

    // Supply a successful link check through the service signal.
    function enterLink(view, url) {
        linkBox(view).text = url;
        Calendar.linkChecked(url, true, "Current calendar", 2, "", 0);
        compare(view.canSubscribe, true);
    }

    function test_reset_and_new_subscribe_reject_late_results_for_same_url() {
        var view = createTemporaryObject(sourceView, tests);
        var url = "https://example.test/calendar";
        enterLink(view, url);
        view.subscribe();
        var oldRequest = view.activeSubscription;
        view.reset();
        enterLink(view, url);
        view.subscribe();
        var newRequest = view.activeSubscription;
        verify(newRequest !== oldRequest);
        Calendar.subscribed(url, "old", "Old failure", oldRequest);
        compare(view.subscribing, true);
        compare(view.message, "");
        compare(view.link, url);

        TestIo.texts["/result.json"] = JSON.stringify({ name: "Current calendar", records: [
            { uid: "one", kind: "event", title: "One", date: "2026-10-05" },
            { uid: "two", kind: "event", title: "Two", date: "2026-10-06" }
        ] });
        var download = TestIo.downloads[1];
        download.stdout.text = "/result.json";
        download.exited(0, 0);
        compare(view.subscribing, false);
        compare(view.message, "subscribed · Current calendar · 2 items");
        compare(view.link, "");
        Calendar.subscribed(url, "old", "Old failure", oldRequest);
        compare(view.message, "subscribed · Current calendar · 2 items");
    }

    function test_reset_rejects_result_before_another_request_starts() {
        var view = createTemporaryObject(sourceView, tests);
        var url = "https://example.test/calendar";
        enterLink(view, url);
        view.subscribe();
        var requestId = view.activeSubscription;
        view.reset();
        Calendar.subscribed(url, "new", "", requestId);
        compare(view.message, "");
        compare(view.activeSubscription, 0);
        enterLink(view, url);
        view.subscribe();
        Calendar.subscribed(url, "", "Download failed", view.activeSubscription);
        compare(view.message, "Download failed");
        compare(view.messageIsError, true);
    }

    function test_subscribe_carries_request_ids_through_downloads_and_immediate_results() {
        var invalid = Calendar.subscribe("bad", "blue");
        var first = Calendar.subscribe("https://example.test/a", "blue");
        var second = Calendar.subscribe("https://example.test/b", "green");
        compare([invalid, first, second], [1, 2, 3]);
        compare(TestIo.downloads.map(function (process) { return process.request.requestId; }), [2, 3]);
        tryCompare(results, "count", 1);
        compare(results.signalArguments[0][3], 1);
        TestIo.texts["/empty.json"] = JSON.stringify({ name: "Empty feed", records: [] });
        TestIo.downloads[1].stdout.text = "/empty.json";
        TestIo.downloads[0].stdout.text = "/empty.json";
        TestIo.downloads[1].exited(0, 0);
        TestIo.downloads[0].exited(0, 0);
        compare(results.signalArguments.map(function (result) { return result[3]; }), [1, 3, 2]);
        Calendar._calendars["l-" + Queries.shortHash("https://example.test/a")] = { id: "existing" };
        var existing = Calendar.subscribe("https://example.test/a", "blue");
        tryCompare(results, "count", 4);
        compare(results.signalArguments[3][3], existing);
        compare(TestIo.downloads.length, 2);
    }
}
