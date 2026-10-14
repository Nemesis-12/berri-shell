import QtQuick

// Runs the real CachedSource with a script that never exits.
// The watchdog must kill it, and the next cycle must start it again.
Item {
    id: test
    property var testSource: test
    property var signals: []
    property int starts: 0

    function started(process) { starts++; }

    function check(ok, message) {
        if (!ok) {
            console.error("CHECK FAILED: " + message);
            Qt.exit(1);
        }
        return ok;
    }

    CachedSource {
        id: source
        name: "hung"
        script: "hung.py"
        age: 40
        runLimit: 30
        versionKey: "version"
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            if (!test.check(test.signals.length >= 2, "kills: " + test.signals.length)) return;
            if (!test.check(test.signals.every(n => n === 9), "signals: " + test.signals)) return;
            if (!test.check(test.starts >= 2, "starts: " + test.starts)) return;
            console.log("Hung script checks passed");
            Qt.exit(0);
        }
    }

    Component.onCompleted: source.open()
}
