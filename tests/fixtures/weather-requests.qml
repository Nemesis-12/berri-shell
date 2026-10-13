import QtQuick

// Holds requests at the external boundary to reproduce late location replies.
Item {
    id: test
    property var config: TEST_CONFIG
    property var service
    property var requests: []
    property int stage: 0

    // Stops on the first wrong visible service value.
    function check(ok, message) {
        if (!ok) {
            console.error(message);
            Qt.exit(1);
        }
        return ok;
    }

    // Supplies the configured place without reading a real location file.
    function readLocation(file) {
        file.contents = JSON.stringify({ latitude: 41.1, longitude: -8.6, name: "Porto, PT" });
        file.loaded();
    }

    // Delays a request until the scenario chooses to complete it.
    function respond(process) {
        if (config.scenario === "name-race" || config.scenario === "geocode-race") {
            var url = process.command[process.command.length - 1];
            if (url.indexOf("api.open-meteo.com/v1/forecast") >= 0) {
                finish(process, forecast(18));
                if (stage === 0) {
                    stage = 1;
                    service.useCoords(38.7, -9.1);
                }
                return;
            }
            if (config.scenario === "geocode-race" && url.indexOf("wttr.in") >= 0) {
                finish(process, { nearest_area: [{ areaName: [{ value: "Lisbon" }], country: [{ value: "Portugal" }] }] });
                return;
            }
            service.useCoords(40.4, -3.7, "Madrid, ES");
            if (config.scenario === "geocode-race")
                finish(process, { results: [{ name: "Madrid", country_code: "PT", latitude: 40.4, longitude: -3.7 }] });
            else finish(process, { nearest_area: [{ areaName: [{ value: "Lisbon" }], country: [{ value: "Portugal" }] }] });
            if (!check(service.locationName === "Madrid, ES", "An old name reply must not replace the configured new name")) return;
            console.log("Weather checks passed for name race");
            Qt.exit(0);
            return;
        }
        requests.push(process);
        advance();
    }

    // Delivers one fixture response in the same signal order as Process.
    function finish(process, response, code) {
        process.running = false;
        process.stdout.text = typeof response === "string" ? response : JSON.stringify(response);
        process.stdout.streamFinished();
        process.exited(code || 0);
    }

    // Gives the places different temperatures so a stale reply is visible.
    function forecast(temp) {
        var response = JSON.parse(JSON.stringify(config.forecast));
        response.current.temperature_2m = temp;
        return response;
    }

    // Exercises publication after a move while the old forecast is in flight.
    function advance() {
        if (config.scenario === "forecast-race") {
            if (stage === 0) {
                stage = 1;
                finish(requests.shift(), forecast(18));
                service.refresh();
            } else if (stage === 1) {
                stage = 2;
                service.useCoords(38.7, -9.1, "Lisbon, PT");
                if (!check(service.model === null && service.updatedAt === 0 && service.locationName === "Lisbon, PT",
                           "A move must clear the old place's readings before showing the new name")) return;
                finish(requests.shift(), forecast(5));
                if (!check(service.model === null && service.error === "", "The old forecast must not publish after a move")) return;
            } else {
                var request = requests.shift();
                if (!check(request.command[request.command.length - 1].indexOf("latitude=38.7&longitude=-9.1") >= 0,
                           "The next forecast must request the latest coordinates")) return;
                finish(request, forecast(25));
                if (!check(service.temperatureC === 25 && service.locationName === "Lisbon, PT" && service.error === "",
                           "The new place must publish its own temperature")) return;
                console.log("Weather checks passed for forecast race");
                Qt.exit(0);
            }
        }
    }

    Component.onCompleted: {
        var component = Qt.createComponent("WeatherUnderTest.qml");
        if (!check(component.status === Component.Ready, component.errorString())) return;
        service = component.createObject(test, { testSource: test });
        check(service !== null, component.errorString());
    }
    Timer { interval: 2000; running: true; onTriggered: test.check(false, "Request scenario did not finish") }
}
