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
 * `keepWhenIdle` also takes answers that arrive while not active. A script
 * that runs longer than `runLimit` gets SIGTERM, then SIGKILL after
 * `killGrace`; the next cycle runs it again. Process.signal() signals the
 * script process only, not its group. A script that starts programs (git,
 * gh) must put them in its own process group and end the group on SIGTERM
 * (see scripts/child_cleanup.py), or they keep running after the kill.
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

    /** Optional source-specific check for fields consumed by its service. */
    property var answerCheck: null

    /** True while at least one view shows this data. Use open() and close(), not a binding: they run in the order the service calls them. */
    property bool active: false

    /** True when the last data stays after the last view hides. */
    property bool keepWhenIdle: false

    /** Longest run time of the script in milliseconds. A script that runs longer is stopped, and the next cycle runs it again. */
    property int runLimit: 120000

    /** Time in milliseconds between SIGTERM and SIGKILL for a script that runs too long. */
    property int killGrace: 3000

    /** True when another source must finish first. */
    property bool blocked: false

    /** Start time of the current cache time. */
    property double checkedAt: 0

    /** Version of the last answer shown. */
    property var version: ""

    /** Time in milliseconds carried by the last accepted answer. */
    property double answeredAt: 0

    readonly property bool running: process.running

    /** True when the source holds an accepted answer. */
    readonly property bool valid: root.version !== ""

    /** A new answer arrived. `data` is the parsed JSON. */
    signal answered(var data)

    /** The script ended, with a good answer or not. */
    signal exited()

    /** True after close() stopped a run. That run ends with no output, which is not a failure to log. */
    property bool stoppedOnHide: false

    /** Last log line time (see SourceFailures.js). */
    property var lastLogged: ({})

    /** True when the last accepted answer is younger than the cache time. It reads the clock at each call, so no timer keeps it current. */
    function isFresh() {
        var age = Date.now() - root.answeredAt;
        return root.valid && age >= 0 && age < root.age;
    }

    /** Run the script now. `force` skips the script's own cache. */
    function start(force) {
        if (process.running) return;
        timer.stop();
        root.stoppedOnHide = false;
        root.checkedAt = Date.now();
        process.command = ["python3", Quickshell.shellPath("scripts/" + root.script)]
            .concat(root.args).concat(force ? ["--force"] : []);
        process.running = true;
        watchdog.restart();
    }

    /** The first view shows: start an old source, or wait for the cache time to end. */
    function open() {
        root.active = true;
        root.check();
    }

    /** The last view hides: stop the timer. */
    function close() {
        root.active = false;
        root.release();
        if (process.running) {
            root.stoppedOnHide = true;
            process.running = false;
            // The run did not finish. A source with `keepWhenIdle` must run again at the next open(), not after its cache time.
            root.checkedAt = 0;
        }
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
        root.answeredAt = 0;
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
        onExited: {
            watchdog.stop();
            forceKill.stop();
            root.exited();
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (!data || typeof data !== "object" || Array.isArray(data))
                        throw new Error("Expected an answer object");
                    var version = data[root.versionKey];
                    var hasVersion = typeof version === "number" ? isFinite(version)
                        : typeof version === "string" && version.length > 0;
                    if (!hasVersion) throw new Error("Missing answer version");
                    if (root.answerCheck && !root.answerCheck(data))
                        throw new Error("Invalid answer fields");
                    if (root.active || root.keepWhenIdle) {
                        var savedAt = typeof version === "number" ? version : Date.parse(version);
                        root.checkedAt = root.cacheAgeStart(savedAt);
                        root.answeredAt = isFinite(savedAt) ? savedAt : Date.now();
                        if (version !== root.version) {
                            root.version = version;
                            root.answered(data);
                        }
                    }
                } catch (e) {
                    // Empty or bad output: keep what the tab shows now.
                    if (!root.stoppedOnHide) root.logFailure(text);
                }
                root.schedule();
            }
        }
    }

    Timer {
        id: watchdog
        interval: root.runLimit
        onTriggered: {
            process.signal(15);
            forceKill.restart();
        }
    }

    Timer {
        id: forceKill
        interval: root.killGrace
        onTriggered: if (process.running) process.signal(9)
    }

    Timer {
        id: timer
        onTriggered: if (!root.blocked) root.start(false)
    }
}
