import QtQuick

// Runs no commands. The source supplies response text and an exit code.
Item {
    property var command: []
    property bool running: false
    property var stdout
    signal exited(int code)
    onRunningChanged: {
        if (running) Qt.callLater(() => owner().testSource.respond(this));
    }

    // The service, which may hold this process inside a shared source part.
    function owner() {
        var item = parent;
        while (item && item.testSource === undefined) item = item.parent;
        return item;
    }
}
