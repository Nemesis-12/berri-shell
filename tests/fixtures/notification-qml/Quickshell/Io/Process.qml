import QtQuick

Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    property string title: ""
    property string message: ""
    signal exited(int exitCode, int exitStatus)

    onRunningChanged: if (running) {
        Qt.callLater(function() {
            ProcessLog.add(root.command);
            root.running = false;
            root.exited(0, 0);
        });
    }
}
