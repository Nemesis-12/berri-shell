import QtQuick

// Holds a pending download so tests can deliver its exit result.
Item {
    id: root
    property bool running: false
    property var command: []
    property var environment: ({})
    property var stdout: null
    signal exited(int code, int status)
    Component.onCompleted: {
        if (root.request !== undefined) TestIo.downloads.push(root);
    }
}
