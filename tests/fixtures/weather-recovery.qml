import QtQuick

// Tests the real Weather QML with synthetic requests and a scaled clock.
Item {
    id: test
    property var config: TEST_CONFIG
    property var service
    property int locationReads: 0
    property int forecasts: 0
    property bool allowed: false
    property real allowedAt: 0

    // Reports the exact failed check to the Node test caller.
    function check(ok, message) {
        if (!ok) {
            console.error(message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    // Fails the first location read and its IP fallback.
    function readLocation(file) {
        locationReads++;
        if (!allowed) file.loadFailed();
        else {
            file.contents = JSON.stringify({ latitude: 41.1, longitude: -8.6, name: "Porto, PT" });
            file.loaded();
        }
    }

    // Allows requests after the first failure; no external service is contacted.
    function respond(process) {
        var isForecast = process.command[process.command.length - 1].indexOf("api.open-meteo.com/v1/forecast") >= 0;
        if (isForecast) forecasts++;
        process.running = false;
        process.stdout.text = allowed && isForecast ? JSON.stringify(config.forecast) : "";
        process.stdout.streamFinished();
        process.exited(allowed ? 0 : 22);
        if (!allowed) {
            allowed = true;
            allowedAt = Date.now();
        }
    }

    Component.onCompleted: {
        var component = Qt.createComponent("WeatherUnderTest.qml");
        if (!check(component.status === Component.Ready, component.errorString())) return;
        service = component.createObject(test, { testSource: test });
        if (!check(service !== null, component.errorString())) return;
        // Change only clock speed. The service still handles its own timer events.
        for (var child of service.resources.concat(service.children)) {
            if (child.interval !== undefined) child.interval *= config.timeScale;
        }
        deadline.start();
    }

    Timer {
        interval: 5
        running: true
        repeat: true
        onTriggered: {
            if (!test.service || !test.service.ready) return;
            if (!test.check(Date.now() - test.allowedAt <= 70000 * test.config.timeScale, "Recovery exceeded 70 seconds")) return;
            if (!test.check(test.service.temperatureC === 18, "Recovered temperature must be 18")) return;
            if (!test.check(test.service.locationName === "Porto, PT", "Recovered location must be Porto")) return;
            console.log("Weather recovered with 18 degrees in " + (Date.now() - test.allowedAt) + " ms");
            Qt.exit(0);
        }
    }
    Timer {
        id: deadline
        interval: 70000 * test.config.timeScale
        onTriggered: test.check(false, "Weather did not recover within 70 seconds")
    }
}
