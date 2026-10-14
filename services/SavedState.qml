import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One saved settings file in ~/.local/state/berri-shell/<name>.json.
 * Reads it once at start and emits `loaded(values)`: the saved object, with
 * `defaults` filling missing keys, or `defaults` when nothing valid is
 * saved. `loadResult` says which: "ok", "missing" (no file), "unreadable"
 * (the file exists but cannot be read) or "invalid" (not a JSON object).
 * `save(values)` writes the object after a short wait, so a burst of saves
 * becomes one write. Before each write the old file is copied to
 * <name>.json.bak (owner-only), and the file is replaced atomically, so a
 * crash never leaves a half-written file. After a read that gave "invalid"
 * or "unreadable", the first save leaves the last good .bak alone and copies
 * the bad file to <name>.json.bad (owner-only) instead, so a hand edit with a
 * typo is not lost. A good save makes the next backup normal again. A write
 * that fails (or whose backup or .bad copy fails) emits `saveFailed(reason)`,
 * sets `saveError` and keeps the change pending (`hasWaitingWrite`); the next `save()` or `writeWaiting()`
 * tries again. A good file is never replaced without a backup.
 */
Scope {
    id: root

    /** File name without ".json". */
    property string name: ""
    /** Value for `loaded` when nothing valid is saved; also fills missing keys. */
    property var defaults: ({})
    /** Wait (ms) that groups a burst of save() calls into one write. */
    property int waitMs: 100

    signal loaded(var values)
    /** The last requested values reached the disk. */
    signal saved()
    /** A write failed. `reason` is short text. The change stays pending. */
    signal saveFailed(string reason)

    readonly property string folder: FolderRoots.state

    /** "", then "ok", "missing", "unreadable" or "invalid" once the file is read. */
    property string loadResult: ""
    /** Reason of the last failed write; "" after a write succeeds. */
    property string saveError: ""
    readonly property bool folderExists: FolderRoots.stateReady
    property string waitingText: ""
    /** True while a requested change is not on disk yet (also after a failed write). */
    property bool hasWaitingWrite: false
    property bool writing: false
    property string writingText: ""
    /** True after a bad read until a save succeeds: the file on disk is not worth a backup. */
    property bool badRead: false

    /** Saves `values` (any plain object). */
    function save(values): void {
        root.waitingText = JSON.stringify(values, null, 2);
        root.hasWaitingWrite = true;
        waitTimer.restart();
    }

    /** Starts the write of the pending change: first the backup (the .bad copy after a bad read), then the file. */
    function writeWaiting(): void {
        if (!root.hasWaitingWrite || !root.folderExists || root.writing) return;
        root.writing = true;
        root.writingText = root.waitingText;
        var command = ["sh", Quickshell.shellPath("scripts/backup-saved.sh"), file.path];
        if (root.badRead) command.push(file.path + ".bad");
        backup.command = command;
        backup.running = true;
    }

    function finishWrite(error: string): void {
        root.writing = false;
        if (error !== "") {
            root.saveError = error;
            root.saveFailed(error);
            return;
        }
        root.saveError = "";
        root.badRead = false;
        if (root.waitingText === root.writingText) root.hasWaitingWrite = false;
        root.saved();
        // A newer change came in during the write.
        if (root.hasWaitingWrite) root.writeWaiting();
    }

    function writeError(error: var): string {
        return error === FileViewError.PermissionDenied ? "Permission denied" : "File write failed";
    }

    function readSaved(text: string, failure: string): void {
        var values = root.defaults;
        var result = failure !== "" ? failure : "invalid";
        if (failure === "") {
            try {
                var stored = JSON.parse(text);
                if (stored && typeof stored === "object") {
                    values = Array.isArray(stored) ? stored : Object.assign({}, root.defaults, stored);
                    result = "ok";
                }
            } catch (e) {
                // No valid saved values: use the defaults.
            }
        }
        root.loadResult = result;
        root.badRead = result === "invalid" || result === "unreadable";
        root.loaded(values);
    }

    Timer {
        id: waitTimer
        interval: root.waitMs
        onTriggered: root.writeWaiting()
    }

    // A pending save starts when the shared folder process finishes.
    onFolderExistsChanged: if (root.folderExists) root.writeWaiting()

    // Copies the old file to <name>.json.bak (<name>.json.bad after a bad read). A failed copy stops the write.
    Process {
        id: backup
        onExited: exitCode => {
            if (exitCode === 0) file.setText(root.writingText);
            else root.finishWrite("Backup failed");
        }
    }

    FileView {
        id: file
        path: root.name !== "" ? root.folder + "/" + root.name + ".json" : ""
        printErrors: false
        atomicWrites: true
        onLoaded: root.readSaved(text(), "")
        onLoadFailed: error => root.readSaved("", error === FileViewError.FileNotFound ? "missing" : "unreadable")
        onSaved: root.finishWrite("")
        onSaveFailed: error => root.finishWrite(root.writeError(error))
    }
}
