import QtQuick
import Quickshell
import Quickshell.Io

/**
 * One saved settings file in ~/.local/state/berri-shell/<name>.json.
 * Reads it once at start and emits `loaded(values)`: the saved object, with
 * `defaults` filling missing keys, or `defaults` when the file is missing or
 * broken. `save(values)` writes the object after a short wait, so a burst of
 * saves becomes one write. The folder is made once, and the file is replaced
 * atomically, so a crash never leaves a half-written file.
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

    readonly property string folder: (Quickshell.env("HOME") || "") + "/.local/state/berri-shell"

    property bool folderExists: false
    property string waitingText: ""
    property bool hasWaitingWrite: false

    /** Saves `values` (any plain object). */
    function save(values): void {
        root.waitingText = JSON.stringify(values, null, 2);
        root.hasWaitingWrite = true;
        waitTimer.restart();
    }

    function writeWaiting(): void {
        if (!root.hasWaitingWrite || !root.folderExists) return;
        root.hasWaitingWrite = false;
        file.setText(root.waitingText);
    }

    function readSaved(text: string): void {
        var values = root.defaults;
        try {
            var stored = JSON.parse(text);
            if (stored && typeof stored === "object") {
                values = Array.isArray(stored) ? stored : Object.assign({}, root.defaults, stored);
            }
        } catch (e) {
            // No valid saved values: use the defaults.
        }
        root.loaded(values);
    }

    Timer {
        id: waitTimer
        interval: root.waitMs
        onTriggered: root.writeWaiting()
    }

    // Makes the folder owner-only (mode 700, files 600) once; a save that comes first waits for it.
    Process {
        running: true
        command: ["sh", Quickshell.shellPath("scripts/private-folder.sh"), root.folder]
        onExited: {
            root.folderExists = true;
            root.writeWaiting();
        }
    }

    FileView {
        id: file
        path: root.name !== "" ? root.folder + "/" + root.name + ".json" : ""
        printErrors: false
        atomicWrites: true
        onLoaded: root.readSaved(text())
        onLoadFailed: root.readSaved("")
    }
}
