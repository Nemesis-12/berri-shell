import QtQuick

// Completes fake brightness commands without starting a system process.
Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    signal exited(int exitCode, int exitStatus)
    onRunningChanged: {
        if (running) {
            ProcessLog.commands = ProcessLog.commands.concat([command.slice()]);
            finish.interval = command.indexOf("set") >= 0 ? 150 : 5;
            finish.start();
        } else {
            finish.stop();
        }
    }
    Timer {
        id: finish
        onTriggered: {
            if (root.command[0] === "sh") {
                root.stdout.text = "panel";
            } else if (root.command.indexOf("set") >= 0) {
                ProcessLog.brightness = parseInt(root.command[root.command.length - 1]);
            } else {
                root.stdout.text = "panel,backlight," + ProcessLog.brightness + "," + ProcessLog.brightness + "%,100";
            }
            if (root.stdout) root.stdout.streamFinished();
            root.running = false;
        }
    }
}
