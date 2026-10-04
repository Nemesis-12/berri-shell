import QtQuick

// Replays synthetic location data without reading the user's saved location.
Item {
    property string path
    property bool printErrors
    property string contents
    signal loaded()
    signal loadFailed()

    function text() { return contents; }
    function reload() {
        Qt.callLater(() => parent.testSource.readLocation(this));
    }
}
