import QtQuick

// Runs no commands. The source supplies response text and an exit code.
Item {
    property var command: []
    property bool running: false
    property var stdout
    signal exited(int code)
    onRunningChanged: {
        if (running) Qt.callLater(() => parent.testSource.respond(this));
    }
}
