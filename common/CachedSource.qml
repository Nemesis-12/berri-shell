import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/SourceFailures.js" as SourceFailures

/**
 * One data source that runs a script and keeps its answer for a cache time.
 * Use one per script, inside a service that counts its viewers (see
 * WhileVisible.qml). The script prints one JSON object that holds a version
 * (`versionKey`): a date string or a time in milliseconds. The cache time
 * and the answer version live here, so every source follows one rule.
 *
 * While `active` is true the source starts its script when the cache time
 * has ended and sets a timer for the time left. A new version fires
 * `answered(data)`. An empty or unreadable answer keeps the last data and
 * writes one line to the shell log (see SourceFailures.js). A source with
 * `keepWhenIdle` also takes answers that arrive while not active.
 */
Scope {
    id: root

    /** Name in the log line, such as "code stats". */
    property string name: ""

    /** File name in the scripts folder. `args` are added after it. */
    property string script: ""
    property var args: []

    /** Cache time in milliseconds. */
    property int age: 0

    /** Name of the version field in the answer. */
    property string versionKey: ""

    /** True while at least one view shows this data. */
    property bool active: false

    /** True when the last data stays after the last view hides. */
    property bool keepWhenIdle: false

    /** True when another source must finish first. */
    property bool blocked: false

    /** Start time of the current cache time. */
    property double checkedAt: 0

    /** Version of the last answer shown. */
    property var version: ""

    readonly property bool running: process.running

    /** A new answer arrived. `data` is the parsed JSON. */
    signal answered(var data)

    /** The script ended, with a good answer or not. */
    signal exited()

    /** Last log line time (see SourceFailures.js). */
    property var lastLogged: ({})

    /** Run the script now. `force` skips the script's own cache. */
    function start(force) {
        if (process.running) return;
        timer.stop();
        root.checkedAt = Date.now();
        process.command = ["python3", Quickshell.shellPath("scripts/" + root.script)]
            .concat(root.args).concat(force ? ["--force"] : []);
        process.running = true;
    }

    /** Start an old source, or set the timer to the time left in the cache time. */
    function check() {
        if (!root.active || root.blocked) return;
        if (Date.now() - root.checkedAt >= root.age) root.start(false);
        else root.schedule();
    }

    /** Stop the timer. A source without `keepWhenIdle` also forgets its age and version. */
    function release() {
        timer.stop();
        if (root.keepWhenIdle) return;
        root.checkedAt = 0;
        root.version = "";
    }

    /** Set the timer to the time left in the cache time. */
    function schedule() {
        if (!root.active) return;
        timer.interval = Math.max(1, root.age - (Date.now() - root.checkedAt));
        timer.restart();
    }

    /** Keep a fresh disk answer's age; retry an old offline answer after one age. */
    function cacheAgeStart(savedAt) {
        var time = Date.now();
        return savedAt > time - root.age && savedAt <= time ? savedAt : time;
    }

    function logFailure(text) {
        var reason = SourceFailures.outputReason(text);
        var line = SourceFailures.report(root.lastLogged, root.name, reason, Date.now());
        if (line !== "") console.warn(line);
    }

    Process {
        id: process
        onExited: root.exited()
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    var version = data[root.versionKey];
                    if (root.active || root.keepWhenIdle) {
                        root.checkedAt = root.cacheAgeStart(typeof version === "number" ? version : Date.parse(version));
                        if (version !== root.version) {
                            root.version = version;
                            root.answered(data);
                        }
                    }
                } catch (e) {
                    // Empty or bad output: keep what the tab shows now.
                    root.logFailure(text);
                }
                root.schedule();
            }
        }
    }

    Timer {
        id: timer
        onTriggered: if (!root.blocked) root.start(false)
    }
}
