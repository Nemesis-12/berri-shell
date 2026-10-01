import QtQuick
import QtQuick.Dialogs
import Quickshell.Io

/**
 * Reusable "pick an image file" flow, shared by Profile (13a) and Sticker
 * (23): opens a portable Qt FileDialog (portal, GTK or Qt's own, picked by
 * Qt itself) starting in startDir if it exists, else fallbackDir. Emits
 * chosen(path) with a plain local path (no "file://" prefix).
 */
Item {
    id: root

    property string dialogTitle: "Choose Image"
    property var nameFilters: ["Images (*.png *.jpg *.jpeg)"]
    property string startDir: ""
    property string fallbackDir: ""

    signal chosen(string path)
    /** Emitted when the dialog closes, after chosen() if a file was picked (also on cancel). */
    signal finished()

    function open() {
        startDirCheck.running = true;
    }

    /** Strips a "file://" URL down to a plain local path. */
    function urlToLocalPath(u) {
        var s = u.toString();
        if (s.indexOf("file://") === 0) s = s.substring(7);
        try { s = decodeURIComponent(s); } catch (e) {}
        return s;
    }

    Process {
        id: startDirCheck
        command: ["test", "-d", root.startDir]
        onExited: (exitCode) => {
            dialog.currentFolder = "file://" + (exitCode === 0 ? root.startDir : root.fallbackDir);
            dialog.open();
        }
    }

    FileDialog {
        id: dialog
        title: root.dialogTitle
        nameFilters: root.nameFilters
        onAccepted: {
            root.chosen(root.urlToLocalPath(selectedFile));
            root.finished();
        }
        onRejected: root.finished()
    }
}
