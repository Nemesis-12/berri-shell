import QtQuick
// Records serialized writes in memory. The user's state file is never opened.
Item {
    property string name
    property int waitMs
    property int saveCount: 0
    property string text: ""
    signal loaded(var values)
    function save(values) {
        text = JSON.stringify(values, null, 2);
        saveCount++;
    }
}
