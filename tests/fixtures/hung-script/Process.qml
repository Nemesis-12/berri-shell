import QtQuick

// Starts a script that never exits. Only SIGKILL ends it: SIGTERM is ignored, like a stuck child.
Item {
    property var command: []
    property bool running: false
    property var stdout
    signal exited(int code)

    onRunningChanged: if (running) owner().started(this)

    // The test root, which holds this process inside the source part.
    function owner() {
        var item = parent;
        while (item && item.testSource === undefined) item = item.parent;
        return item.testSource;
    }

    function signal(number) {
        owner().signals.push(number);
        if (number !== 9) return;
        running = false;
        stdout.streamFinished();
        exited(number);
    }
}
