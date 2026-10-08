import QtQuick

// Logs the command, runs it on the fake disk and reports the exit.
Item {
    id: root
    property var command: []
    property bool running: false
    property var environment: ({})
    property var stdout: null
    signal exited(int exitCode, int exitStatus)
    onRunningChanged: if (running) {
        Disk.log("run", command.slice());
        finish.start();
    }
    Timer {
        id: finish
        interval: 1
        onTriggered: {
            var code = Disk.run(root.command);
            root.running = false;
            root.exited(code, 0);
        }
    }
}
