import QtQuick
import Qt.labs.folderlistmodel

// Checks the installed folder watch with files supplied by the test caller.
QtObject {
    id: root
    property bool fileAdded: false
    property bool ready: false
    property var folder: FolderListModel {
        folder: Qt.resolvedUrl("../../scratchpad/calendar-files-71")
        nameFilters: ["*.ics"]
        showDirs: false
        showHidden: false
        caseSensitive: true
        onStatusChanged: {
            if (status === FolderListModel.Ready && !root.ready) {
                root.ready = true;
                console.log("watch-ready");
            }
        }
        onCountChanged: {
            if (count === 1 && !root.fileAdded) {
                root.fileAdded = true;
                console.log("watch-added");
            } else if (count === 0 && root.fileAdded) {
                console.log("watch-removed");
                Qt.exit(0);
            }
        }
    }
    property var deadline: Timer {
        interval: 5000
        running: true
        onTriggered: { console.error("Folder watch timed out"); Qt.exit(1); }
    }
}
