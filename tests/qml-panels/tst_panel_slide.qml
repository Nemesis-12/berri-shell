import QtQuick
import QtTest
import qs.common

// The shared slide operation: close steps, close-before-dialog order, tab requests, and
// the per-monitor rule with two fake monitors. No shell instance, no real input.
Item {
    id: host
    width: 200
    height: 200

    // Two monitors, each with a pill and a picker. Same timeline as the real pill (1260 ms, rest at 484 ms).
    Component {
        id: slideType
        PanelSlide { totalMs: 1260; closeEndMs: 484 }
    }
    property var pillA
    property var pillB
    property var pickerA
    property var pickerB
    property var events: []

    Component {
        id: requestsType
        PanelRequests {}
    }

    TestCase {
        name: "PanelSlide"
        when: windowShown

        function init() {
            host.pillA = createTemporaryObject(slideType, host, { screenName: "A", kind: "pill" });
            host.pillB = createTemporaryObject(slideType, host, { screenName: "B", kind: "pill" });
            host.pickerA = createTemporaryObject(slideType, host, { screenName: "A", kind: "picker" });
            host.pickerB = createTemporaryObject(slideType, host, { screenName: "B", kind: "picker" });
            host.events = [];
        }

        function cleanup() {
            for (const panel of [host.pillA, host.pillB, host.pickerA, host.pickerB]) panel.closeAtOnce();
        }

        function test_open_runs_in_a_straight_line_to_the_full_time() {
            host.pillA.openSlide();
            compare(host.pillA.open, true);
            compare(host.pillA.slide.duration, 1260);
            compare(host.pillA.slide.to, 1);
            compare(host.pillA.slide.easing.type, Easing.Linear);
            tryCompare(host.pillA, "progress", 1, 3000);
            compare(host.pillA.elapsedMs, 1260);
        }

        function test_close_from_open_ends_at_the_rest_time_and_eases_out() {
            host.pillA.openSlide();
            tryCompare(host.pillA, "progress", 1, 3000);
            host.pillA.closeSlide();
            compare(host.pillA.closeFromOpen, true);
            compare(host.pillA.closing, true);
            compare(host.pillA.slide.to, 484 / 1260);
            // 1260 ms * (1 - 484/1260) = 776 ms.
            compare(host.pillA.slide.duration, 776);
            tryCompare(host.pillA, "progress", 0, 3000);
            compare(host.pillA.active, false);
            compare(host.pillA.closeFromOpen, false);
        }

        function test_close_from_midway_plays_the_open_back_to_zero() {
            host.pillA.openSlide();
            wait(300);
            verify(host.pillA.progress > 0 && host.pillA.progress < 1);
            const at = host.pillA.progress;
            host.pillA.closeSlide();
            compare(host.pillA.closeFromOpen, false);
            compare(host.pillA.closing, false);
            compare(host.pillA.slide.to, 0);
            verify(Math.abs(host.pillA.slide.duration - Math.round(1260 * at)) <= 30);
            tryCompare(host.pillA, "progress", 0, 3000);
        }

        function test_close_at_once_resets_without_the_close_finished_signal() {
            const finished = createTemporaryObject(signalSpyType, host, { target: host.pillA, signalName: "closeFinished" });
            host.pillA.openSlide();
            wait(100);
            host.pillA.closeAtOnce();
            compare(host.pillA.progress, 0);
            compare(host.pillA.open, false);
            compare(finished.count, 0);
        }

        function test_dialog_waits_for_the_panel_at_rest() {
            host.pillA.openSlide();
            tryCompare(host.pillA, "progress", 1, 3000);
            host.pillA.closeThenRun(() => host.events.push("dialog"), true);
            // The close has started, the dialog has not.
            compare(host.pillA.open, false);
            compare(host.events.length, 0);
            verify(host.pillA.progress > 0);
            tryCompare(host.pillA, "progress", 0, 3000);
            compare(host.events, ["dialog"]);
        }

        function test_dialog_without_waiting_runs_as_the_close_starts() {
            host.pillA.openSlide();
            tryCompare(host.pillA, "progress", 1, 3000);
            host.pillA.closeThenRun(() => host.events.push(host.pillA.open ? "open" : "closing"), false);
            compare(host.events, ["closing"]);
            verify(host.pillA.progress > 0);
        }

        function test_dialog_with_the_panel_at_rest_runs_at_once() {
            host.pillA.closeThenRun(() => host.events.push("dialog"), true);
            compare(host.events, ["dialog"]);
        }

        function test_dialog_runs_when_the_close_is_at_once() {
            host.pillA.openSlide();
            tryCompare(host.pillA, "progress", 1, 3000);
            host.pillA.closeThenRun(() => host.events.push("dialog"), true);
            host.pillA.closeAtOnce();
            compare(host.events, ["dialog"]);
        }

        // ---- per monitor

        function test_picker_open_closes_the_pill_of_that_monitor_first_with_its_normal_close() {
            host.pillA.openSlide();
            host.pillB.openSlide();
            tryCompare(host.pillA, "progress", 1, 3000);
            tryCompare(host.pillB, "progress", 1, 3000);

            host.pickerA.openSlide();
            // The pill of monitor A closes with its normal close, not at once.
            compare(host.pillA.open, false);
            compare(host.pillA.closing, true);
            compare(host.pillA.slide.to, 484 / 1260);
            verify(host.pillA.progress > 0, "The pill is still on its way");
            // Monitor B is not affected.
            compare(host.pillB.open, true);
            compare(host.pillB.progress, 1);
            compare(host.pickerB.open, false);
            tryCompare(host.pillA, "progress", 0, 3000);
            compare(host.pickerA.open, true);
        }

        function test_pill_open_closes_the_picker_of_that_monitor_only() {
            host.pickerA.openSlide();
            host.pickerB.openSlide();
            host.pillB.openSlide();
            compare(host.pickerB.open, false);
            compare(host.pickerA.open, true);
            compare(host.pillB.open, true);
            compare(host.pillA.open, false);
        }

        function test_a_closed_panel_frees_the_monitor() {
            host.pillA.openSlide();
            host.pillA.closeAtOnce();
            host.pickerA.openSlide();
            compare(host.pillA.open, false);
            compare(host.pickerA.open, true);
            host.pickerA.closeAtOnce();
            host.pillA.openSlide();
            compare(host.pickerA.open, false);
        }

        // ---- tab requests

        function test_tab_requests_close_first_then_reopen_the_panel() {
            const requests = createTemporaryObject(requestsType, host);
            requests.dialogRequested.connect((openDialog, afterClose) => host.pillA.closeThenRun(openDialog, afterClose));
            requests.reopenRequested.connect(() => { host.events.push("reopen"); host.pillA.openSlide(); });
            host.pillA.openSlide();
            tryCompare(host.pillA, "progress", 1, 3000);
            // The dialog (here: at once finished) asks to reopen the panel.
            requests.dialogRequested(() => {
                host.events.push("dialog");
                // A real dialog ends later, not inside the close.
                Qt.callLater(() => requests.reopenRequested());
            }, true);
            compare(host.events.length, 0);
            tryCompare(host.events, "length", 2, 3000);
            compare(host.events, ["dialog", "reopen"]);
            compare(host.pillA.open, true);
        }
    }

    Component {
        id: signalSpyType
        SignalSpy {}
    }
}
