pragma Singleton
import QtQuick

// Keeps the fake system: started commands, files, and the screen temperature.
QtObject {
    property var commands: []
    property var files: []
    property int temperature: 6500
    property var saved: ({ "power-modes": { ac: "saver", battery: "saver" } })

    // Does what the real command would do and returns its exit code.
    function run(command, stdout) {
        if (command[0] === "test") return files.indexOf(command[2]) >= 0 ? 0 : 1;
        if (command[0] === "cp") {
            files = files.concat([command[3]]);
            return 0;
        }
        if (command[0] === "hyprctl") {
            stdout.text = String(temperature);
            return 0;
        }
        if (command[0] === "bash") {
            temperature = parseInt(/temperature (\d+)/.exec(command[2])[1]);
            return 0;
        }
        return 1;
    }
}
