import QtQuick

// Runs a real data service with synthetic script answers. Each round replaces
// every answer; the Node caller counts the log lines the service wrote.
Item {
    id: test
    property var config: TEST_CONFIG
    property var service
    property int round: 0
    property int answered: 0
    property int perRound: config.service === "code" ? 3 : 1

    // Reports the exact failed check to the Node test caller.
    function check(ok, message) {
        if (!ok) {
            console.error("CHECK FAILED: " + message);
            Qt.exit(1);
        }
        return ok;
    }

    // The location file of the weather service.
    function readLocation(file) {
        file.contents = JSON.stringify({ latitude: 41.1, longitude: -8.6, name: "Porto, PT" });
        file.loaded();
    }

    // Answer of one script call in the current round: { text, code }.
    function answerFor(command) {
        var step = config.rounds[Math.min(round, config.rounds.length - 1)];
        var last = command[command.length - 1] + " " + (command[1] || "");
        for (var key in step) if (last.indexOf(key) >= 0) return step[key];
        return step["*"];
    }

    function respond(process) {
        var answer = answerFor(process.command);
        process.running = false;
        process.stdout.text = answer.text;
        process.stdout.streamFinished();
        process.exited(answer.code);
        if (++answered % perRound === 0) Qt.callLater(next);
    }

    function next() {
        round++;
        if (round >= config.rounds.length) {
            if (!checks()) return;
            console.log("Failure log checks passed");
            Qt.exit(0);
            return;
        }
        service.refresh();
    }

    Component.onCompleted: {
        var component = Qt.createComponent("ServiceUnderTest.qml");
        if (!check(component.status === Component.Ready, component.errorString())) return;
        service = component.createObject(test, { testSource: test });
        if (config.service === "usage") service.viewers = 1;
        else if (config.service === "code") service.refresh();
        deadline.start();
    }

    // After the last round the service must still hold the data of the first round.
    function checks() {
        if (config.service === "usage")
            return check(service.claudeSessionPercent === 42, "Failed refresh must keep the last reading");
        if (config.service === "code")
            return check(service.days.length === 1, "Failed refresh must keep the last days");
        return check(service.temperatureC === 18 && service.updatedAt > 0, "Failed refresh must keep the last forecast");
    }

    Timer {
        id: deadline
        interval: 8000
        onTriggered: test.check(false, "Rounds did not finish")
    }
}
