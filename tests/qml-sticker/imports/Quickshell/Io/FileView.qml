import QtQuick

// A file watcher that never reports a change.
QtObject {
    property string path: ""
    property bool watchChanges: false
    property bool preload: true
    property bool printErrors: true
    signal fileChanged()
    signal loadFailed(var error)
}
