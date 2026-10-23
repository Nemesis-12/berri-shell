import QtQuick

// Records the command, answers the sticker search, and ends with exit code 0.
Item {
    id: root
    property var command: []
    property bool running: false
    property var stdout: null
    signal exited(int exitCode)
    onRunningChanged: {
        if (running) {
            ProcessLog.commands = ProcessLog.commands.concat([command.slice()]);
            finish.start();
        } else {
            finish.stop();
        }
    }
    Timer {
        id: finish
        interval: 5
        onTriggered: {
            if (root.stdout) {
                root.stdout.text = root.command[1] === "-c" ? ProcessLog.stickerFile + "\n" : "";
                root.stdout.streamFinished();
            }
            root.running = false;
            root.exited(0);
        }
    }
}
