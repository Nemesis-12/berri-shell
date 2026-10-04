pragma Singleton
import QtQuick

// Stores command payloads and the fake backlight value for boundary checks.
QtObject { property var commands: []; property real brightness: 40 }
