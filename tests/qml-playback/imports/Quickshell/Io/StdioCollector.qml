import QtQuick

// Delivers fake process output to the real service.
QtObject { property string text: ""; property bool waitForEnd: false; signal streamFinished() }
