import QtQuick
import QtTest
import Quickshell.Hyprland
import qs.notifications

// Tests the pop-up's public inputs without a Pill object or desktop window.
TestCase {
    id: testCase
    name: "NotificationPopupInterface"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    property var alertsAtRequest: null

    NotificationPopup {
        id: popup
        anchors.fill: parent
        anchorRect: Qt.rect(101, 10, 124, 30)
        dpr: 1
        dashboardOpen: false
        screenName: "test"
        onOpenAlertsRequested: testCase.alertsAtRequest = {
            current: popup._current,
            active: popup.active,
            queued: popup._queue.length,
            read: Notifications.all[0].read
        }
    }

    NotificationPopup {
        id: other
        anchors.fill: parent
        anchorRect: Qt.rect(101, 10, 124, 30)
        dpr: 1
        dashboardOpen: false
        screenName: "other"
    }

    // Supplies a snapshot at the same interface used by the notification store.
    function item(id, urgency) {
        return { id: id, urgency: urgency || "critical", appName: "Test", appIcon: "", summary: id,
            body: "", time: Date.now(), actions: [] };
    }

    // Reset only the public inputs and pop-up state between checks.
    function init() {
        popup._hideNow();
        popup._queue = [];
        mouseMove(popup, 990, 690);
        popup._showMs = 5000;
        other._hideNow();
        other._queue = [];
        Hyprland.focusedMonitor = { name: "test" };
        popup.anchorRect = Qt.rect(101, 10, 124, 30);
        popup.dpr = 1;
        popup.dashboardOpen = false;
        popup.blocked = false;
        popup.screenName = "test";
        testCase.alertsAtRequest = null;
    }

    function test_anchorAtBothMonitorScales_data() {
        return [
            { tag: "HDMI-A-1", scale: 1, anchor: Qt.rect(101, 10, 124, 30), fullX: -27 },
            { tag: "eDP-2", scale: 2, anchor: Qt.rect(101.5, 10, 124, 30), fullX: -26.5 },
            { tag: "HDMI-A-1-hover", scale: 1, anchor: Qt.rect(69, 10, 188, 30), fullX: -27 },
            { tag: "eDP-2-hover", scale: 2, anchor: Qt.rect(69.5, 10, 188, 30), fullX: -26.5 },
            { tag: "HDMI-A-1-tray", scale: 1, anchor: Qt.rect(-31, 10, 388, 30), fullX: -27 },
            { tag: "eDP-2-tray", scale: 2, anchor: Qt.rect(-30.5, 10, 388, 30), fullX: -26.5 }
        ];
    }

    // The input mask follows the same start and end rectangles on both scales.
    function test_anchorAtBothMonitorScales(data) {
        popup.anchorRect = data.anchor;
        popup.dpr = data.scale;
        popup._receive(item("first"));
        compare(popup.cardX, data.anchor.x);
        compare(popup.cardY, 10);
        compare(popup.cardWidth, data.anchor.width);
        compare(popup.cardHeight, 30);
        verify(popup.active);
        tryCompare(popup, "_progress", 1, 10000);
        compare(popup.cardX, data.fullX);
        compare(popup.cardWidth, 380);
        compare(popup.cardHeight, 76);
        popup._close();
        tryCompare(popup, "cardWidth", 0, 10000);
        compare(popup.active, false);
        compare(popup.cardHeight, 0);
    }

    // Newest arrivals replace the card; waiting cards return newest first after each shrink.
    function test_queueWaitsForClose() {
        popup._receive(item("first"));
        popup._receive(item("second"));
        popup._receive(item("third"));
        compare(popup._current.id, "third");
        compare(popup._queue.map(function (n) { return n.id; }), ["first", "second"]);
        tryCompare(popup, "_progress", 1, 10000);
        popup._close();
        compare(popup._current.id, "third");
        tryVerify(function () { return popup._current !== null && popup._current.id === "second"; }, 10000);
        compare(popup._queue.map(function (n) { return n.id; }), ["first"]);
        tryCompare(popup, "_progress", 1, 10000);
        popup._close();
        tryVerify(function () { return popup._current !== null && popup._current.id === "first"; }, 10000);
        compare(popup._queue.length, 0);
        verify(popup.active);
    }

    // The dashboard hides the card. Critical and transient items have no other home, so they wait for the close.
    function test_dashboardKeepsItemsThatWouldBeLost() {
        popup._receive(item("waiting"));
        popup._receive(item("current"));
        popup.dashboardOpen = true;
        compare(popup._current, null);
        compare(popup._queue.map(function (n) { return n.id; }), ["waiting"]);
        compare(popup.cardWidth, 0);
        compare(popup.active, false);
        popup._receive(item("critical-during"));
        popup._receive(Object.assign(item("transient-during", "normal"), { transient: true }));
        popup._receive(item("stored-normal", "normal"));
        compare(popup._current, null);
        compare(popup._queue.map(function (n) { return n.id; }), ["waiting", "critical-during", "transient-during"]);
        compare(popup.active, false);
        popup.dashboardOpen = false;
        compare(popup._current.id, "transient-during");
        compare(popup._queue.map(function (n) { return n.id; }), ["waiting", "critical-during"]);
        verify(popup.active);
        popup._receive(item("after-dashboard"));
        compare(popup._current.id, "after-dashboard");
    }

    // The monitor input keeps arrivals on the focused monitor.
    function test_focusedMonitorReceivesCards() {
        popup.screenName = "other";
        popup._receive(item("elsewhere"));
        compare(popup._current, null);
        popup.screenName = "test";
        popup._receive(item("here"));
        compare(popup._current.id, "here");
        verify(popup.active);
    }

    // A normal card closes 5 s after it opens.
    function test_normalCardClosesAfterFiveSeconds() {
        var start = Date.now();
        popup._receive(item("normal", "normal"));
        tryCompare(popup, "_progress", 1, 10000);
        tryVerify(function () { return !popup._open; }, 6000);
        var shown = Date.now() - start;
        verify(shown >= 4900 && shown <= 5600, "Card stayed " + shown + " ms");
    }

    // Critical cards stay until the person dismisses them.
    function test_criticalCardStays() {
        popup._showMs = 200;
        popup._receive(item("critical"));
        wait(500);
        verify(popup._open);
    }

    // Hover pauses the timeout and keeps the time that was left.
    function test_hoverPausesAndKeepsRemainingTime() {
        popup._showMs = 2000;
        var start = Date.now();
        popup._receive(item("normal", "normal"));
        tryCompare(popup, "_progress", 1, 10000);
        wait(300);
        mouseMove(popup, popup.cardX + popup.cardWidth / 2, popup.cardY + 40);
        var shownBeforeHover = Date.now() - start;
        tryVerify(function () { return popup._hovered; }, 500);
        wait(2500);
        verify(popup._open, "Hover did not pause the timeout");
        var left = Date.now();
        mouseMove(popup, 990, 690);
        tryVerify(function () { return !popup._open; }, 3000);
        var waited = Date.now() - left;
        // The full timeout would be 2000 ms. About 2000 - shownBeforeHover is left.
        verify(waited < 2000 - shownBeforeHover + 400, "Timeout restarted in full: " + waited + " ms after " + shownBeforeHover + " ms");
    }

    // Waiting cards follow the focus. The card on screen finishes where it is.
    function test_waitingCardsFollowFocusToTheOtherMonitor() {
        popup._receive(item("first"));
        popup._receive(item("second"));
        popup._receive(item("third"));
        compare(popup._queue.map(function (n) { return n.id; }), ["first", "second"]);
        Hyprland.focusedMonitor = { name: "other" };
        tryVerify(function () { return other._current !== null; }, 10000);
        compare(popup._queue.length, 0);
        compare(popup._current.id, "third");
        compare(other._current.id, "second");
        compare(other._queue.map(function (n) { return n.id; }), ["first"]);
        tryCompare(popup, "_progress", 1, 10000);
        popup._close();
        tryCompare(popup, "cardWidth", 0, 10000);
        compare(popup._current, null);
    }

    // Without a focused monitor nothing can take the cards, so they wait.
    function test_waitingCardsStayWhenNoMonitorHasFocus() {
        popup._receive(item("first"));
        popup._receive(item("second"));
        Hyprland.focusedMonitor = null;
        wait(50);
        compare(popup._queue.map(function (n) { return n.id; }), ["first"]);
    }

    // Fullscreen drops normal cards and keeps critical ones, current or waiting.
    function test_fullscreenRules() {
        popup.blocked = true;
        popup._receive(item("blocked-normal", "normal"));
        compare(popup._current, null);
        popup._receive(item("allowed-critical"));
        compare(popup._current.id, "allowed-critical");
        popup.blocked = false;
        popup._receive(item("normal-on-top", "normal"));
        compare(popup._queue[0].id, "allowed-critical");
        popup._receive(item("normal-waiting", "normal"));
        popup.blocked = true;
        compare(popup._current.id, "allowed-critical");
        compare(popup._queue.length, 0);
    }

    // A queued critical card survives when fullscreen hides a normal one.
    function test_fullscreenKeepsQueuedCritical() {
        popup._receive(item("waiting-critical"));
        popup._receive(item("normal-on-top", "normal"));
        popup.blocked = true;
        compare(popup._current.id, "waiting-critical");
        compare(popup._queue.length, 0);
    }

    // The pill is hidden in fullscreen, so a click must not open a dashboard that nothing reveals.
    function test_fullscreenCardClickDoesNotOpenAlerts() {
        popup.blocked = true;
        popup._receive(item("critical"));
        tryCompare(popup, "_progress", 1, 10000);
        mouseClick(popup, popup.cardX + popup.cardWidth / 2, popup.cardY + 20);
        compare(testCase.alertsAtRequest, null);
        compare(popup._current.id, "critical");
        popup.blocked = false;
        mouseClick(popup, popup.cardX + popup.cardWidth / 2, popup.cardY + 20);
        compare(testCase.alertsAtRequest.current, null);
    }

    // The host gets its navigation request only after the notification is read and the card is gone.
    function test_alertsRequestAfterReadAndHide() {
        var stored = Object.assign(item("alerts"), { read: false, snoozedUntil: 0 });
        Notifications.all = [stored];
        popup._receive(stored);
        popup._receive(item("queued"));
        popup._receive(stored);
        popup._openAlerts();
        compare(testCase.alertsAtRequest, { current: null, active: false, queued: 2, read: true });
        compare(popup.cardWidth, 0);
    }
}
