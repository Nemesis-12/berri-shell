import QtQuick

// Tests the real Weather QML with synthetic requests and a scaled clock.
Item {
    id: test
    property var config: TEST_CONFIG
    property real now: Date.parse(config.forecast.current.time + "Z") - config.forecast.utc_offset_seconds * 1000
    property var service
    property int locationReads: 0
    property int forecasts: 0
    property bool allowed: ["move", "shared", "retained", "clock", "partial", "missing-primary", "missing-hour"].indexOf(config.scenario) >= 0
    property real allowedAt: 0
    property bool moved: false
    property int ticks: 0
    property var forecastTimer
    property bool failed: false
    property int stage: 0
    property var lastGood
    property real observedAt: 0
    // Longest unscaled wait of the service timers, except the 15 minute forecast timer. A retry waits this long.
    property real longestRetryWaitMs: 0

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
        if (config.scenario === "partial") {
            response.current.relative_humidity_2m = null;
            response.current.wind_direction_10m = null;
            response.hourly.uv_index[0] = null;
        }
        if (config.scenario === "missing-primary" && forecasts === 2) response.current.temperature_2m = null;
        if (config.scenario === "missing-hour" && forecasts === 2) response.current.time = "2026-10-02T06:15";
        if (["retained", "missing-primary", "missing-hour"].indexOf(config.scenario) >= 0 && forecasts >= 3) response.current.temperature_2m = 23.5;
        process.running = false;
        process.stdout.text = allowed && isForecast ? JSON.stringify(response) : "";
        if (!allowed && config.scenario === "invalid-location")
            process.stdout.text = JSON.stringify({ nearest_area: [{ latitude: "bad", longitude: "-8.6" }] });
        process.stdout.streamFinished();
        process.exited(allowed || ["bad-data", "invalid-location"].indexOf(config.scenario) >= 0 ? 0 : 22);
        if (!allowed && (["location", "invalid-location"].indexOf(config.scenario) >= 0 || isForecast)) {
            var expectedError = config.scenario === "bad-data" ? "Bad data"
                : isForecast || config.scenario === "location" ? "Offline" : "No location";
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
                else longestRetryWaitMs = Math.max(longestRetryWaitMs, child.interval);
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
            if (test.config.scenario === "clock") {
                if (test.stage === 0) {
                    if (!test.check(test.service.hours[0].time === "2026-09-30T06:00", "The initial strip must start at 06")) return;
                    test.service.error = "Offline";
                    test.now += 60 * 60 * 1000;
                    test.stage++;
                    return;
                }
                if (test.stage === 1) {
                    if (!test.check(test.service.hours[0].time === "2026-09-30T07:00"
                                    && test.service.stripHours(0)[0].time === "2026-09-30T07:00",
                                    "Retained strip hours must follow the minute clock")) return;
                    if (!test.check(test.forecasts === 1 && test.service.error === "Offline", "Advancing the clock must not fetch or clear an error")) return;
                    test.now += 60 * 60 * 1000;
                    test.stage++;
                    return;
                }
                if (!test.check(test.service.hours.length === 0 && test.service.stripHours(0).length === 0,
                                "An exhausted forecast must not show a past hour as NOW")) return;
                console.log("Weather checks passed for the retained clock");
                Qt.exit(0);
                return;
            }
            if (test.config.scenario === "partial") {
                if (!test.check(test.service.temperatureC === 18 && test.service.humidity === null
                                && test.service.dayDetail(0).humidity === null && test.service.windDirection === ""
                                && test.service.uvIndex === null && test.service.uvLabel === "" && test.service.error === "",
                                "Missing optional values must stay missing in all current readers")) return;
                console.log("Weather checks passed for partial readings");
                Qt.exit(0);
                return;
            }
            if (["retained", "missing-primary", "missing-hour"].indexOf(test.config.scenario) >= 0) {
                if (test.service.loading) return;
                if (test.stage === 0) {
                    test.lastGood = test.service.model;
                    test.observedAt = test.service.updatedAt;
                    if (test.config.scenario === "retained") test.allowed = false;
                    test.stage = 1;
                    test.service.refresh();
                    return;
                }
                if (test.forecasts === 2) {
                    if (!test.check(test.service.model === test.lastGood && test.service.temperatureC === 18,
                                    "Failed refresh must retain the last good result")) return;
                    var expected = test.config.scenario === "retained" ? "Offline" : "Bad data";
                    if (!test.check(test.service.error === expected && test.service.updatedAt === test.observedAt,
                                    "Failed refresh must report " + expected + " and keep the last timestamp")) return;
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
            // Real time depends on machine load, so the test checks the wait the service chose, not the time it took.
            if (test.config.scenario !== "shared"
                && !test.check(test.longestRetryWaitMs > 0 && test.longestRetryWaitMs <= 70000, "A retry waits longer than 70 seconds")) return;
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
        interval: 120000 // Real time. Stops a hung run before the 180 second limit of the Node test.
        onTriggered: test.check(false, "Weather did not recover")
    }
}
