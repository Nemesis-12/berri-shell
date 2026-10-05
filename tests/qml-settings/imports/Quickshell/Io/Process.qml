import QtQuick

// Runs a fake command through ProcessLog and then reports its exit.
Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    signal exited(int exitCode)
    onRunningChanged: {
        if (running) {
            ProcessLog.commands = ProcessLog.commands.concat([command.slice()]);
            finish.interval = command[0] === "bash" ? 300 : 5;
            finish.start();
        } else {
            finish.stop();
        }
    }
    Timer {
        id: finish
        onTriggered: {
            const code = ProcessLog.run(root.command, root.stdout);
            if (root.stdout) root.stdout.streamFinished();
            root.running = false;
            root.exited(code);
        }
    }
}
