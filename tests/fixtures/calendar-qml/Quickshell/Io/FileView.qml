import QtQuick

// Implements the read and write results used by CalendarFiles and Theme.
Item {
    property string path: ""
    property bool blockLoading: false
    property bool blockWrites: false
    property bool printErrors: true
    property bool atomicWrites: false
    property bool watchChanges: false
    property bool preload: true
    signal loaded()
    signal loadFailed(var error)
    signal fileChanged()
    signal saved()
    signal saveFailed(var error)
    function text() {
        if (TestIo.deniedReads[path]) throw new Error("Permission denied");
        return TestIo.texts[path] || "";
    }
    function setText(value) {
        if (TestIo.failWrite) saveFailed(FileViewError.PermissionDenied);
        else { TestIo.texts[path] = value; TestIo.writes = TestIo.writes.concat([path]); saved(); }
    }
    function reload() { loaded(); }
    // A preloading view reports its first read like Quickshell does.
    Component.onCompleted: {
        if (!preload || !path) return;
        if (TestIo.deniedReads[path]) loadFailed(FileViewError.PermissionDenied);
        else if (TestIo.texts[path] === undefined) loadFailed(FileViewError.FileNotFound);
        else loaded();
    }
}
