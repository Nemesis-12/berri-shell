import QtQuick
import qs.services
import qs.tabs.weather

// Drives the actual day rows and both crossfade copies across forecast changes.
Window {
    id: test
    visible: true
    width: 800
    height: 454
    property int stage: 0

    WeatherTab { id: tab; anchors.fill: parent }

    // Builds only service-boundary day summaries, with distinct dates.
    function days(start, count) {
        var out = [];
        for (var i = 0; i < count; i++)
            out.push({ date: "2026-10-" + String(start + i).padStart(2, "0"), code: 3,
                       minC: 10, maxC: 20, precipProbability: 0 });
        return out;
    }

    // Walks view items without sending desktop input.
    function descendants(item) {
        var out = [item];
        for (var child of item.children || []) out = out.concat(descendants(child));
        return out;
    }

    // Stops with the exact failed view check.
    function check(ok, message) {
        if (ok) return true;
        console.error(message);
        Qt.exit(1);
        return false;
    }

    // Selects through the day row's public click signal.
    function pick(date) {
        var row = descendants(tab).find(item => item.day && item.day.date === date && item.clicked);
        if (!check(row !== undefined, "The requested day row must exist")) return;
        row.clicked();
    }

    // Checks the displayed label and safe indices in both crossfade copies.
    function checkCards(label) {
        for (var item of descendants(tab)) {
            if (!item.whenLabel) continue;
            if (!check(item.day >= 0 && item.day < Math.max(1, Weather.days.length), "Both card copies must have a valid day")) return false;
            if (item.visible && !check(item.whenLabel() === label, "The visible card must stay on " + label)) return false;
        }
        return true;
    }

    Component.onCompleted: Weather.days = days(9, 7)
    Timer {
        interval: 400
        running: true
        repeat: true
        onTriggered: {
            if (test.stage === 0) test.pick("2026-10-11");
            else if (test.stage === 1) {
                if (!test.check(tab.selectedDay === 2, "October 11 starts at index 2")) return;
                Weather.days = test.days(10, 7);
            } else if (test.stage === 2) {
                if (!test.check(tab.selectedDay === 1, "October 11 must stay selected after midnight")) return;
                if (!test.checkCards("SUN 11")) return;
                Weather.days = test.days(11, 1);
            } else if (test.stage === 3) {
                if (!test.check(tab.selectedDay === 0, "The selected date becomes today's current conditions")) return;
                if (!test.checkCards("NOW")) return;
                Weather.days = test.days(12, 1);
            } else if (test.stage === 4) {
                if (!test.check(tab.selectedDay === 0, "An absent date falls back to today")) return;
                if (!test.checkCards("NOW")) return;
                Weather.days = [];
            } else {
                if (!test.checkCards("NOW")) return;
                console.log("Weather selection checks passed");
                Qt.exit(0);
            }
            test.stage++;
        }
    }
}
