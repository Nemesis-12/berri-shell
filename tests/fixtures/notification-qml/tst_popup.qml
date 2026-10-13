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

    NotificationPopup {
        id: popup
        anchors.fill: parent
        anchorRect: Qt.rect(101, 10, 124, 30)
        dpr: 1
        dashboardOpen: false
        screenName: "test"
    }

    // Supplies a snapshot at the same interface used by the notification store.
    function item(id) {
        return { id: id, urgency: "critical", appName: "Test", appIcon: "", summary: id,
            body: "", time: Date.now(), actions: [] };
    }

    // Reset only the public inputs and pop-up state between checks.
    function init() {
        popup.hideNow();
        popup.anchorRect = Qt.rect(101, 10, 124, 30);
        popup.dpr = 1;
        popup.dashboardOpen = false;
        popup.blocked = false;
    }

    function test_anchorAtBothMonitorScales_data() {
        return [
            { tag: "HDMI-A-1", scale: 1, anchor: Qt.rect(101, 10, 124, 30), fullX: -27 },
            { tag: "eDP-2", scale: 2, anchor: Qt.rect(101.5, 10, 124, 30), fullX: -26.5 }
        ];
    }

    // The input mask follows the same start and end rectangles on both scales.
    function test_anchorAtBothMonitorScales(data) {
        popup.anchorRect = data.anchor;
        popup.dpr = data.scale;
        popup.receive(item("first"));
        compare(popup.cardX, data.anchor.x);
        compare(popup.cardY, 10);
        compare(popup.cardWidth, 124);
        compare(popup.cardHeight, 30);
        verify(popup.active);
        tryCompare(popup, "progress", 1, 1000);
        compare(popup.cardX, data.fullX);
        compare(popup.cardWidth, 380);
        compare(popup.cardHeight, 76);
        popup.close();
        tryCompare(popup, "cardWidth", 0, 1000);
        compare(popup.active, false);
        compare(popup.cardHeight, 0);
    }
}
