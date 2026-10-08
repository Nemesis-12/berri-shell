import QtQuick

// Reads and writes the fake disk with the signals of Quickshell's FileView.
Item {
    id: root
    property string path: ""
    property bool printErrors: true
    property bool atomicWrites: false
    property bool blockLoading: false
    property bool blockWrites: false
    property bool watchChanges: false
    property bool preload: true
    signal fileChanged()
    function reload() { loaded(); }
    signal loaded()
    signal loadFailed(var error)
    signal saved()
    signal saveFailed(var error)
    function text() { return Disk.files[path] || ""; }
    function setText(value) {
        Disk.log("write", { path: path, text: value });
        write.value = value;
        write.start();
    }
    Timer {
        id: write
        property string value: ""
        interval: 1
        onTriggered: {
            if (Disk.unwritable[root.path]) { root.saveFailed(FileViewError.PermissionDenied); return; }
            Disk.files[root.path] = value;
            root.saved();
        }
    }
    Component.onCompleted: {
        if (!path) return;
        if (Disk.unreadable[path]) loadFailed(FileViewError.PermissionDenied);
        else if (Disk.files[path] === undefined) loadFailed(FileViewError.FileNotFound);
        else loaded();
    }
}
