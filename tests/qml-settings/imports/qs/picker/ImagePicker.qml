import QtQuick

// Fake picture chooser: open() chooses the picture in `pickedPath`.
Item {
    property string dialogTitle: ""
    property var nameFilters: []
    property string startDir: ""
    property string fallbackDir: ""
    property string pickedPath: "/tmp/chosen.png"
    signal chosen(string path)
    function open() { chosen(pickedPath); }
}
