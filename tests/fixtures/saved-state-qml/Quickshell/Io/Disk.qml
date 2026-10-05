pragma Singleton
import QtQml

// A disk in memory. `events` lists every command and write in the order they happen.
QtObject {
    property var files: ({})
    /** Paths whose read or write fails with a permission error. */
    property var unreadable: ({})
    property var unwritable: ({})
    property bool failBackup: false
    property var events: []
    function reset() { files = ({}); unreadable = ({}); unwritable = ({}); failBackup = false; events = []; }
    function log(kind, value) { events = events.concat([{ kind: kind, value: value }]); }
    /** Commands that were started, as arrays. */
    function commands() { return events.filter(e => e.kind === "run").map(e => e.value); }
    /** Does what the real command does and returns its exit code. */
    function run(command) {
        if (command[1] && command[1].indexOf("backup-saved.sh") >= 0) {
            var file = command[2];
            if (failBackup) return 1;
            if (files[file] !== undefined) files[file + ".bak"] = files[file];
        }
        return 0;
    }
}
