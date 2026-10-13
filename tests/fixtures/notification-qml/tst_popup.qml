import QtQuick
import QtTest
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
            current: popup.current,
            active: popup.active,
            queued: popup.queue.length,
            read: Notifications.all[0].read
        }
    }

    // Supplies a snapshot at the same interface used by the notification store.
    function item(id, urgency) {
        return { id: id, urgency: urgency || "critical", appName: "Test", appIcon: "", summary: id,
            body: "", time: Date.now(), actions: [] };
    }

    // Reset only the public inputs and pop-up state between checks.
    function init() {
        popup.hideNow();
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
        popup.receive(item("first"));
        compare(popup.cardX, data.anchor.x);
        compare(popup.cardY, 10);
        compare(popup.cardWidth, data.anchor.width);
        compare(popup.cardHeight, 30);
        verify(popup.active);
        tryCompare(popup, "progress", 1, 10000);
        compare(popup.cardX, data.fullX);
        compare(popup.cardWidth, 380);
        compare(popup.cardHeight, 76);
        popup.close();
        tryCompare(popup, "cardWidth", 0, 10000);
        compare(popup.active, false);
        compare(popup.cardHeight, 0);
    }

    // Newest arrivals replace the card; waiting cards return newest first after each shrink.
    function test_queueWaitsForClose() {
        popup.receive(item("first"));
        popup.receive(item("second"));
        popup.receive(item("third"));
        compare(popup.current.id, "third");
        compare(popup.queue.map(function (n) { return n.id; }), ["first", "second"]);
        tryCompare(popup, "progress", 1, 10000);
        popup.close();
        compare(popup.current.id, "third");
        tryVerify(function () { return popup.current !== null && popup.current.id === "second"; }, 10000);
        compare(popup.queue.map(function (n) { return n.id; }), ["first"]);
        tryCompare(popup, "progress", 1, 10000);
        popup.close();
        tryVerify(function () { return popup.current !== null && popup.current.id === "first"; }, 10000);
        compare(popup.queue.length, 0);
        verify(popup.active);
    }

    // Keep the current dashboard policy for this prefactor, including dropped critical arrivals.
    function test_dashboardHidesAndRejectsCards() {
        popup.receive(item("waiting"));
        popup.receive(item("current"));
        popup.dashboardOpen = true;
        compare(popup.current, null);
        compare(popup.queue.length, 0);
        compare(popup.cardWidth, 0);
        popup.receive(item("during-dashboard"));
        compare(popup.current, null);
        popup.dashboardOpen = false;
        popup.receive(item("after-dashboard"));
        compare(popup.current.id, "after-dashboard");
        verify(popup.active);
    }

    // The monitor input keeps arrivals on the focused monitor.
    function test_focusedMonitorReceivesCards() {
        popup.screenName = "other";
        popup.receive(item("elsewhere"));
        compare(popup.current, null);
        popup.screenName = "test";
        popup.receive(item("here"));
        compare(popup.current.id, "here");
        verify(popup.active);
    }

    // Fullscreen still drops normal cards and allows critical cards.
    function test_fullscreenRules() {
        popup.blocked = true;
        popup.receive(item("blocked-normal", "normal"));
        compare(popup.current, null);
        popup.receive(item("allowed-critical"));
        compare(popup.current.id, "allowed-critical");
        popup.blocked = false;
        popup.receive(item("normal-on-top", "normal"));
        compare(popup.queue[0].id, "allowed-critical");
        popup.blocked = true;
        compare(popup.current, null);
        compare(popup.queue.length, 0);
        compare(popup.cardWidth, 0);
    }

    // The host gets its navigation request only after the notification is read and the card is gone.
    function test_alertsRequestAfterReadAndHide() {
        var stored = Object.assign(item("alerts"), { read: false, snoozedUntil: 0 });
        Notifications.all = [stored];
        popup.receive(stored);
        popup.receive(item("queued"));
        popup.receive(stored);
        popup.openAlerts();
        compare(testCase.alertsAtRequest, { current: null, active: false, queued: 0, read: true });
        compare(popup.cardWidth, 0);
    }
}
