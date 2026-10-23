pragma Singleton
import QtQuick

QtObject {
    property var commands: []
    function reset() { commands = []; }
    function add(command) { commands = commands.concat([command.slice()]); }
}
