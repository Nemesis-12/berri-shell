import QtQuick

// Completes fake brightness commands without starting a system process.
// A command stopped before it finished ends its stream with no text, like a killed program.
Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    signal exited(int exitCode, int exitStatus)
    onRunningChanged: {
        if (running) {
            ProcessLog.commands = ProcessLog.commands.concat([command.slice()]);
            finish.interval = command.indexOf("set") >= 0 ? 150
                : ProcessLog.holdScriptProcesses && command[0] === "python3" ? 10000 : 5;
            finish.start();
        } else if (finish.running) {
            finish.stop();
            if (stdout) {
                stdout.text = "";
                stdout.streamFinished();
            }
        }
    }
    Timer {
        id: finish
        onTriggered: {
            if (root.command[0] === "sh") {
                root.stdout.text = "panel";
            } else if (root.command.indexOf("set") >= 0) {
                ProcessLog.brightness = parseInt(root.command[root.command.length - 1]);
            } else if (root.command[0] === "python3" && ProcessLog.scriptAnswer !== "") {
                root.stdout.text = ProcessLog.scriptAnswer;
            } else {
                root.stdout.text = "panel,backlight," + ProcessLog.brightness + "," + ProcessLog.brightness + "%,100";
            }
            if (root.stdout) root.stdout.streamFinished();
            root.running = false;
        }
    }
}
