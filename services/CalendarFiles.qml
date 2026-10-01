import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

/** Watches calendar files, writes them atomically and downloads calendar feeds. */
Scope {
    id: root

    required property string folder
    property bool active: false
    property var paths: []
    property bool folderReady: false
    property var removedPaths: ({})
    property bool listingAgain: false

    signal listed(var paths)
    signal read(string path, string text, bool failed)
    signal downloaded(var request, int code, string text)

    /** Reads a small import file at once. Null means it could not be read. */
    function readNow(path: string): var {
        var reader = importReader.createObject(root, { path: path });
        var text = null;
        try { text = reader.text(); } catch (e) { text = null; }
        reader.destroy();
        return text;
    }

    /** Reports the result of each atomic write before returning. */
    function write(path: string, text: string, report: var): void {
        var writer = calendarWriter.createObject(root, { path: path, report: report });
        if (!writer) { report(false, "File writer could not start"); return; }
        writer.setText(text);
        writer.destroy();
    }

    function writeError(error: var): string {
        if (error === FileViewError.PermissionDenied) return "Permission denied";
        if (error === FileViewError.NotAFile) return "Path is not a file";
        if (error === FileViewError.FileNotFound) return "File not found";
        return "File write failed";
    }

    /** Keeps a removed file out of listings until its deletion has finished. */
    function removeFile(path: string): void {
        removedPaths[path] = true;
        Quickshell.execDetached(["rm", "-f", path]);
    }

    /** Starts one bounded download. The request stays with its result. */
    function download(request: var): void {
        feedDownload.createObject(root, { request: request });
    }

    /** Rechecks the folder after a watch change or the slow safety check. */
    function checkFolder(): void {
        if (!active || !folderReady) return;
        if (folderCheck.running) { listingAgain = true; return; }
        folderCheck.running = true;
    }

    function publishFiles(files: var): void {
        var present = {};
        for (var i = 0; i < files.length; i++) present[files[i]] = true;
        for (var path in removedPaths) if (!present[path]) delete removedPaths[path];
        listed(files.filter(function (path) { return !removedPaths[path]; }));
    }

    // Keep existing readers alive when the calendar list changes.
    onPathsChanged: {
        var wanted = {};
        for (var i = 0; i < paths.length; i++) wanted[paths[i]] = true;
        for (var row = calendarPaths.count - 1; row >= 0; row--)
            if (!wanted[calendarPaths.get(row).filePath]) calendarPaths.remove(row);
        var present = {};
        for (var p = 0; p < calendarPaths.count; p++) present[calendarPaths.get(p).filePath] = true;
        for (var path in wanted) if (!present[path]) calendarPaths.append({ filePath: path });
    }

    Component { id: importReader; FileView { blockLoading: true; printErrors: false } }
    Component {
        id: calendarWriter
        FileView {
            required property var report
            blockWrites: true
            atomicWrites: true
            printErrors: false
            onSaved: report(true, "")
            onSaveFailed: error => report(false, root.writeError(error))
        }
    }

    ListModel { id: calendarPaths }
    Instantiator {
        model: calendarPaths
        delegate: FileView {
            required property string filePath
            path: filePath
            watchChanges: true
            atomicWrites: true
            blockWrites: true
            printErrors: false
            onLoaded: root.read(filePath, text(), false)
            onLoadFailed: root.read(filePath, "", true)
            onFileChanged: reload()
        }
    }

    // Create the cache folder before a feed or edit can write to it.
    Process {
        running: root.active && !root.folderReady
        command: ["mkdir", "-p", root.folder + "/subscriptions"]
        onExited: (code, status) => {
            if (code !== 0) return;
            root.folderReady = true;
            root.checkFolder();
        }
    }

    // Qt's installed folder type uses the filesystem watch. Quickshell has no folder type.
    FolderListModel {
        id: calendarFolder
        folder: root.folderReady ? Qt.resolvedUrl("file://" + root.folder) : ""
        nameFilters: ["*.ics"]
        showDirs: false
        showHidden: false
        caseSensitive: true
        onCountChanged: folderWait.restart()
        onStatusChanged: if (status === FolderListModel.Ready) folderWait.restart()
    }
    Connections {
        target: calendarFolder
        function onDataChanged() { folderWait.restart(); }
        function onModelReset() { folderWait.restart(); }
    }
    Timer { id: folderWait; interval: 25; onTriggered: root.checkFolder() }

    // A slow independent listing catches a lost folder or removal watch.
    Process {
        id: folderCheck
        command: ["find", "-L", root.folder, "-maxdepth", "1", "-type", "f", "-name", "*.ics", "!", "-name", ".*", "-print"]
        stdout: StdioCollector { id: foundFiles }
        onExited: (code, status) => {
            if (root.listingAgain) {
                root.listingAgain = false;
                Qt.callLater(root.checkFolder);
            } else if (code === 0) {
                root.publishFiles(foundFiles.text.split("\n").filter(function (path) { return path !== ""; }).sort());
            }
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.active && root.folderReady
        onTriggered: root.checkFolder()
    }

    // One curl per request. Exit code 63 means the feed exceeds 10 MB.
    Component {
        id: feedDownload
        Process {
            id: download
            required property var request
            running: true
            command: ["sh", "-c",
                't=$(mktemp) || exit 1; curl -fsSL --max-time 15 --max-filesize 10485760 -o "$t" "$1" || { c=$?; rm -f "$t"; exit $c; }; ' +
                '[ "$(wc -c <"$t")" -gt 10485760 ] && { rm -f "$t"; exit 63; }; cat "$t"; rm -f "$t"',
                "sh", request.url]
            stdout: StdioCollector { id: downloadedText }
            onExited: (code, status) => {
                root.downloaded(download.request, code, downloadedText.text);
                download.destroy();
            }
        }
    }
}
