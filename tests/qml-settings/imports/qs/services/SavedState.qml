import QtQuick
import Quickshell.Io

// Fake saved file: it reports ProcessLog.saved[name] when it starts.
Item {
    property string name: ""
    property var defaults: ({})
    property var values: ({})
    signal loaded()
    function save(values) {}
    Component.onCompleted: {
        values = Object.assign({}, defaults, ProcessLog.saved[name] || {});
        loaded();
    }
}
