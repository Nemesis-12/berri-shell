import QtQuick

// Starts a script that never exits. Only a signal ends it, like a real hung child.
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
        running = false;
        stdout.streamFinished();
        exited(number);
    }
}
