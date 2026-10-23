pragma Singleton
import QtQuick

// Stores command payloads and the fake backlight value for boundary checks.
QtObject {
    property var commands: []
    property real brightness: 40
    property bool holdScriptProcesses: false
    // When not empty, a python3 script answers with this text.
    property string scriptAnswer: ""
}
