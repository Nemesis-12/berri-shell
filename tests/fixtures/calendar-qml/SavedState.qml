import QtQuick

// Keeps settings in memory without reading or changing saved user data.
Item {
    property string name: ""
    property var defaults: ({})
    property var values: ({})
    signal loaded(var values)
    function save(next) { values = next; }
}
