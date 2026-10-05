import QtQuick
import Quickshell.Io

// Fake saved file: it reports ProcessLog.saved[name] when it starts.
Item {
    property string name: ""
    property var defaults: ({})
    signal loaded(var values)
    function save(values) {}
    Component.onCompleted: loaded(Object.assign({}, defaults, ProcessLog.saved[name] || {}))
}
