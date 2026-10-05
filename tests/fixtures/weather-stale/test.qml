import QtQuick
import qs.common
import qs.services
import qs.tabs.weather

// Drives the real weather parts with a stand-in service and checks what they show.
Item {
    id: test
    width: 600
    height: 400
    property int step: 0
    readonly property real base: Date.UTC(2026, 9, 4, 12, 0, 0)

    CurrentWeather { id: cell; x: 0; y: 0; width: 240; height: 64 }
    WeatherCard { id: card; x: 0; y: 100; width: 300; height: 272 }

    function fail(message) {
        console.error("CHECK FAILED: " + message);
        Qt.exit(1);
    }

    function walk(item, visit) {
        visit(item);
        for (var i = 0; i < item.children.length; i++) walk(item.children[i], visit);
    }

    // First visible item of the view whose text matches.
    function textItem(view, pattern) {
        var found = null;
        walk(view, function (it) {
            if (!found && it.visible && typeof it.text === "string" && pattern.test(it.text)) found = it;
        });
        return found;
    }

    function iconColor(view) {
        var found = null;
        walk(view, function (it) {
            if (!found && it.visible && it.name === "cloud") found = it;
        });
        return found ? String(found.color) : "none";
    }

    function chipText(view) {
        var it = textItem(view, /AGO$|^NO DATA$|^JUST NOW$/);
        return it ? it.text : "";
    }

    function tempColor(view, pattern) {
        var it = textItem(view, pattern);
        return it ? String(it.color) : "none";
    }

    function expect(actual, wanted, message) {
        if (actual !== wanted) fail(message + ": got " + actual + ", wanted " + wanted);
    }

    function run() {
        var dim = String(Theme.dim), fg = String(Theme.fg), accent = String(Theme.accentLight);
        if (step === 0) {
            Weather.updatedAt = base;
            Clock.minute = new Date(base);
            expect(chipText(cell), "", "No chip while data is current (cell)");
            expect(chipText(card), "", "No chip while data is current (card)");
            expect(tempColor(cell, /^24°$/), fg, "Temperature color when current (cell)");
            expect(iconColor(cell), accent, "Icon color when current (cell)");
            expect(test.textItem(cell, /^CLOUDY$/) !== null, true, "Condition label when current");
            expect(Clock.viewers, 0, "Clock must not run while no chip shows");
            Weather.updatedAt = base - 120 * 60000;
            Weather.error = "Offline";
        } else if (step === 1) {
            expect(chipText(cell), "2 H AGO", "Chip text (cell)");
            expect(chipText(card), "2 H AGO", "Chip text (card)");
            expect(tempColor(cell, /^24°$/), dim, "Temperature dims on error (cell)");
            expect(tempColor(card, /^24$/), dim, "Temperature dims on error (card)");
            expect(iconColor(cell), dim, "Icon dims on error (cell)");
            expect(iconColor(card), dim, "Icon dims on error (card)");
            expect(test.textItem(cell, /^CLOUDY$/), null, "Chip replaces the condition label");
            expect(test.textItem(card, /^Updated /), null, "Chip replaces the update time");
            expect(Clock.viewers, 2, "Each visible chip counts one clock viewer");
            Clock.minute = new Date(base + 60 * 60000);
        } else if (step === 2) {
            expect(chipText(cell), "3 H AGO", "Chip age follows the minute clock (cell)");
            expect(chipText(card), "3 H AGO", "Chip age follows the minute clock (card)");
            Weather.updatedAt = 0;
        } else if (step === 3) {
            expect(chipText(cell), "NO DATA", "Chip text before the first reading");
            Weather.error = "";
            Weather.updatedAt = base;
        } else if (step === 4) {
            expect(chipText(cell), "", "Chip hides when the error clears");
            expect(tempColor(cell, /^24°$/), fg, "Temperature color returns");
            expect(iconColor(cell), accent, "Icon color returns");
            expect(Clock.viewers, 0, "Clock stops when the chips hide");
            console.log("Weather stale checks passed");
            Qt.exit(0);
            return;
        }
        step++;
        wait.restart();
    }

    // Waits longer than the 300 ms fade after each change.
    Timer { id: wait; interval: 450; running: true; onTriggered: test.run() }
}
