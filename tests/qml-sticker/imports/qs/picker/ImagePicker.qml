import QtQuick

// Fake picture chooser. The sticker test never opens it.
Item {
    property string dialogTitle: ""
    property var nameFilters: []
    property string startDir: ""
    property string fallbackDir: ""
    signal chosen(string path)
    function open() {}
}
