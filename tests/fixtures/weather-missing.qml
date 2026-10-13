import QtQuick
import qs.services
import qs.tabs.weather

// Checks existing weather text elements with unknown readings and an offline source.
Window {
    id: test
    visible: true
    width: 800
    height: 600

    CurrentWeather { id: cell; width: 300; height: 80 }
    WeatherCard { id: card; y: 80; width: 300; height: 272 }
    WeatherReadouts { id: readouts; x: 300; y: 80; width: 180; height: 272 }
    WeatherHours { id: hours; y: 352; width: 480; height: 182; clock24: true }
    WeatherDayRow {
        id: day
        x: 481
        y: 80
        width: 318
        height: 60
        day: ({ date: "2026-03-08", code: null, minC: null, maxC: null, precipProbability: null })
    }

    // Reads the rendered text values, including nested rows and columns.
    function texts(item) {
        var out = typeof item.text === "string" ? [item.text] : [];
        for (var child of item.children || []) out = out.concat(texts(child));
        return out;
    }

    // Stops on the first incorrect value shown by the real views.
    function check(ok, message) {
        if (ok) return true;
        console.error(message);
        Qt.exit(1);
        return false;
    }

    Component.onCompleted: {
        Weather.ready = false;
        Weather.error = "Offline";
        Weather.updatedAt = 0;
    }
    Timer {
        interval: 450
        running: true
        onTriggered: {
            if (!test.check(test.texts(cell).indexOf("-°") >= 0, "Home must use the single-hyphen temperature placeholder")) return;
            if (!test.check(test.texts(card).indexOf("-") >= 0, "The card must use the existing missing-value placeholder")) return;
            if (!test.check(test.texts(readouts).indexOf("Dew point -°") >= 0
                            && test.texts(readouts).indexOf("- mm expected") >= 0,
                            "Readout details must not turn missing values into zero")) return;
            if (!test.check(test.texts(hours).indexOf("-°") >= 0 && test.texts(day).indexOf("-°") >= 0,
                            "Hourly and daily temperatures must show missing values")) return;
            if (!test.check(!test.texts(test).some(text => /NO DATA|NaN|undefined|null|^0(?:°|$| mm)/.test(text)),
                            "Unknown weather must not show status captions or fake zeros")) return;
            console.log("Weather missing view checks passed");
            Qt.exit(0);
        }
    }
}
