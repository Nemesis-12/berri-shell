import QtQuick

// Tests the real Weather QML with synthetic requests and a scaled clock.
Item {
    id: test
    property var config: TEST_CONFIG
    property var service
    property int locationReads: 0
    property int forecasts: 0
    property bool allowed: ["move", "shared", "retained"].indexOf(config.scenario) >= 0
    property real allowedAt: 0
    property bool moved: false
    property int ticks: 0
    property var forecastTimer
    property bool failed: false
    property int stage: 0
    property var lastGood
    property real observedAt: 0

    // Reports the exact failed check to the Node test caller.
    function check(ok, message) {
        if (!ok) {
            failed = true;
            console.error(message);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    // All current readers must agree when the service publishes a result.
    Connections {
        target: test.service || null
        function onModelChanged() {
            if (test.config.scenario === "shared")
                test.check(test.service.temperatureC === test.service.dayDetail(0).tempC,
                           "Current weather readers disagree at publication");
        }
    }

    // Fails the first location read and its IP fallback.
    function readLocation(file) {
        locationReads++;
        if (!allowed && ["location", "invalid-location"].indexOf(config.scenario) >= 0) file.loadFailed();
        else {
            file.contents = JSON.stringify(moved
                ? { latitude: 38.7, longitude: -9.1, name: "Lisbon, PT" }
                : { latitude: 41.1, longitude: -8.6, name: "Porto, PT" });
            file.loaded();
        }
    }

    // Allows requests after the first failure; no external service is contacted.
    function respond(process) {
        var isForecast = process.command[process.command.length - 1].indexOf("api.open-meteo.com/v1/forecast") >= 0;
        if (isForecast) forecasts++;
        var response = JSON.parse(JSON.stringify(config.forecast));
        if (config.scenario === "retained" && forecasts >= 3) response.current.temperature_2m = 23.5;
        process.running = false;
        process.stdout.text = allowed && isForecast ? JSON.stringify(response) : "";
        if (!allowed && config.scenario === "invalid-location")
            process.stdout.text = JSON.stringify({ nearest_area: [{ latitude: "bad", longitude: "-8.6" }] });
        process.stdout.streamFinished();
        process.exited(allowed || ["bad-data", "invalid-location"].indexOf(config.scenario) >= 0 ? 0 : 22);
        if (!allowed && (["location", "invalid-location"].indexOf(config.scenario) >= 0 || isForecast)) {
            var expectedError = config.scenario === "bad-data" ? "Bad data"
                : isForecast ? "Offline" : "No location";
            check(service.error === expectedError, "Failure must keep the existing error value " + expectedError);
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
            if (child.interval !== undefined) {
                if (child.interval === 15 * 60 * 1000) forecastTimer = child;
                child.interval *= config.timeScale;
            }
        }
        deadline.start();
    }

    Timer {
        interval: 5
        running: true
        repeat: true
        onTriggered: {
            if (test.failed || !test.service || !test.service.ready) return;
            if (test.config.scenario === "retained") {
                if (test.service.loading) return;
                if (test.stage === 0) {
                    test.lastGood = test.service.model;
                    test.allowed = false;
                    test.stage = 1;
                    test.service.refresh();
                    return;
                }
                if (test.forecasts === 2) {
                    if (!test.check(test.service.model === test.lastGood && test.service.temperatureC === 18,
                                    "Failed refresh must retain the last good result")) return;
                    if (!test.check(test.service.error === "Offline", "Failed refresh must report Offline")) return;
                    return;
                }
                if (!test.check(test.forecasts === 3 && test.service.temperatureC === 24
                                && test.service.dayDetail(0).tempC === 24 && test.service.error === "",
                                "Retry must publish 24 degrees and clear the error")) return;
                console.log("Weather checks passed for retained readings and retry");
                Qt.exit(0);
                return;
            }
            if (test.config.scenario === "move") {
                if (test.service.loading || test.forecasts !== test.ticks + 1) return;
                if (test.ticks === 0) {
                    test.forecastTimer.stop();
                    test.moved = true;
                }
                if (test.ticks < 4) {
                    if (!test.check(test.locationReads === 1, "Location must stay cached for three ticks")) return;
                    test.ticks++;
                    test.forecastTimer.triggered();
                    return;
                }
                if (!test.check(test.locationReads === 2, "Fourth forecast tick must resolve location once")) return;
                if (!test.check(test.service.latitude === 38.7 && test.service.longitude === -9.1,
                                "Fourth tick must use the new coordinates")) return;
                if (!test.check(test.service.locationName === "Lisbon, PT", "Fourth tick must show Lisbon")) return;
                console.log("Weather checks passed for hourly location resolution");
                Qt.exit(0);
                return;
            }
            if (test.config.scenario !== "shared"
                && !test.check(Date.now() - test.allowedAt <= 70000 * test.config.timeScale, "Recovery exceeded 70 seconds")) return;
            if (!test.check(test.service.temperatureC === 18, "Recovered temperature must be 18")) return;
            if (!test.check(test.service.locationName === "Porto, PT", "Recovered location must be Porto")) return;
            if (test.config.scenario === "shared") {
                if (test.observedAt === 0) test.observedAt = Date.now();
                if (Date.now() - test.observedAt < 60000 * test.config.timeScale) return;
                if (!test.check(test.forecasts === 1 && test.service.error === "",
                                "Success must stop short retries")) return;
            }
            if (test.config.scenario !== "shared")
                console.log("Weather recovered with 18 degrees in " + (Date.now() - test.allowedAt) + " ms");
            console.log("Weather checks passed for recovery");
            Qt.exit(0);
        }
    }
    Timer {
        id: deadline
        interval: 70000 * test.config.timeScale
        onTriggered: test.check(false, "Weather did not recover within 70 seconds")
    }
}
