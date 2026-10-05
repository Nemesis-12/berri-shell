import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

/** Watches calendar files, writes them atomically and downloads calendar feeds. */
Scope {
    id: root

    required property string folder
    readonly property string parser: Quickshell.shellPath("tools/feed-to-records/feed-to-records")
    // Exit codes of the download and parse scripts. Calendar.qml turns them into text.
    readonly property int exitParserMissing: 127
    readonly property int exitNotCalendar: 70
    readonly property int exitSaveFailed: 71
    property bool active: false
    property var paths: []
    property bool folderReady: false
    property var removedPaths: ({})
    property bool listingAgain: false
    /** Time between safety scans, in ms. */
    readonly property int safetyScanMs: 300000
    /** How many views of the calendar are visible now (see WhileVisible.qml). A scan runs when the first one opens. */
    property int viewers: 0

    signal listed(var paths)
    signal read(string path, string text, bool failed)
    signal downloaded(var request, int code, string jsonPath)
    signal parserMissing()
    /** The parser ran on a saved subscription and failed. The old records file may still be read. */
    signal convertFailed(string jsonPath)

    /** Reads a file once and releases the reader. Null means the read failed. */
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

    /** Short text for a `FileViewError` value of a failed write. */
    function writeError(error: var): string {
        if (error === FileViewError.PermissionDenied) return "Permission denied";
        if (error === FileViewError.NotAFile) return "Path is not a file";
        if (error === FileViewError.FileNotFound) return "File not found";
        return "File write failed";
    }

    /** Keeps a removed file out of listings until its deletion has finished. */
    function removeFile(path: string): void {
        removedPaths[path] = true;
        if (path.indexOf(root.folder + "/subscriptions/") === 0)
            Quickshell.execDetached(["rm", "-f", path, recordPath(path)]);
        else Quickshell.execDetached(["rm", "-f", path]);
    }

    /** Starts one bounded download. The request stays with its result. */
    function download(request: var): void {
        var process = feedDownload.createObject(root, { request: request });
        if (process) activeDownloads.push(process);
    }

    property var activeDownloads: []

    /** Stops the downloads of one calendar. Their results are dropped, never reported. */
    function cancelDownloads(calendarId: string): void {
        for (var i = 0; i < activeDownloads.length; i++) {
            var process = activeDownloads[i];
            if (process.request.calendarId !== calendarId || process.request.purpose === "check") continue;
            process.cancelled = true;
            process.running = false;
        }
    }

    property var freshening: ({})

    /** The compact record file that goes with a subscription's .ics file. */
    function recordPath(icsPath: string): string {
        return icsPath.replace(/\.ics$/, ".json");
    }

    /** True when a path is the compact record file of a subscription. */
    function isRecordFile(path: string): bool {
        return path.indexOf(root.folder + "/subscriptions/") === 0;
    }

    /**
     * Starts reading one calendar file. A subscription first gets its records
     * made again from its .ics file, so a changed system time zone or a newer
     * .ics file never leaves old clock times. Reading waits for that.
     */
    function openReader(path: string): void {
        if (!isRecordFile(path)) { calendarPaths.append({ filePath: path }); return; }
        if (freshening[path]) return;
        freshening[path] = true;
        recordFreshener.createObject(root, { jsonPath: path });
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
        for (var path in wanted) if (!present[path]) openReader(path);
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
            readonly property bool isLink: root.isRecordFile(filePath)
            path: filePath
            watchChanges: true
            preload: !isLink
            atomicWrites: true
            blockWrites: true
            printErrors: false
            Component.onCompleted: if (isLink) readLink()
            function readLink(): void {
                var content = root.readNow(filePath);
                root.read(filePath, content === null ? "" : content, content === null || content === "");
            }
            onLoaded: root.read(filePath, text(), false)
            // A missing file is an empty calendar. Any other error is a failed read.
            onLoadFailed: error => root.read(filePath, "", error !== FileViewError.FileNotFound)
            onFileChanged: {
                if (isLink) readLink();
                else reload();
            }
        }
    }

    Component {
        id: recordFreshener
        Process {
            required property string jsonPath
            running: true
            command: ["sh", "-c",
                '[ -f "$2" ] || exit 0; [ -x "$1" ] || exit ' + root.exitParserMissing + '; "$1" "$2" "$3"',
                "sh", root.parser, jsonPath.replace(/\.json$/, ".ics"), jsonPath]
            onExited: (code, status) => {
                delete root.freshening[jsonPath];
                if (code === root.exitParserMissing) root.parserMissing();
                else if (code !== 0) root.convertFailed(jsonPath);
                if (root.paths.indexOf(jsonPath) >= 0) calendarPaths.append({ filePath: jsonPath });
                destroy();
            }
        }
    }

    // Create the owner-only calendar folder before a feed or edit can write to it.
    Process {
        running: root.active && !root.folderReady
        command: ["sh", Quickshell.shellPath("scripts/private-folder.sh"), root.folder, root.folder + "/subscriptions"]
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
    // The folder watch reports changes. This check only covers a lost watch, so
    // it is rare: a file removed outside the app shows within 5 minutes.
    // A scan also runs when the Calendar tab opens (see viewers).
    Timer {
        interval: root.safetyScanMs
        repeat: true
        running: root.active && root.folderReady
        onTriggered: root.checkFolder()
    }
    onViewersChanged: if (viewers === 1) checkFolder()

    // Download and convert in a child process. No ICS text enters QML.
    Component {
        id: feedDownload
        Process {
            id: download
            required property var request
            property bool cancelled: false
            running: true
            command: ["sh", Quickshell.shellPath("scripts/feed-download.sh"), request.url, root.parser,
                request.purpose === "check" ? "" : root.folder + "/subscriptions/" + request.calendarId,
                root.folder + "/subscriptions",
                String(root.exitParserMissing), String(root.exitNotCalendar), String(root.exitSaveFailed)]
            stdout: StdioCollector { id: outputPath }
            onExited: (code, status) => {
                root.activeDownloads = root.activeDownloads.filter(function (other) { return other !== download; });
                if (!download.cancelled) root.downloaded(download.request, code, outputPath.text.trim());
                download.destroy();
            }
        }
    }
}
