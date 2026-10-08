import QtQml

// Supplies the text collected from a test process.
QtObject {
    property string text: ""
    property bool waitForEnd: false
    signal streamFinished()
}
