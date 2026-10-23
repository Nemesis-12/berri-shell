import QtQuick

// Delivers fake process output to the real code.
QtObject { property string text: ""; property bool waitForEnd: false; signal streamFinished() }
