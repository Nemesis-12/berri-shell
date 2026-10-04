pragma Singleton
import QtQuick

// Gives services a shell path without starting Quickshell.
QtObject { function shellPath(name) { return "/fixture/" + name; } }
