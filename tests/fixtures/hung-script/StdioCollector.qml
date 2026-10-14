import QtQml

// Delivers a complete synthetic response at the request boundary.
QtObject {
    property bool waitForEnd
    property string text
    signal streamFinished()
}
