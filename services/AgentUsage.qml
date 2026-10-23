pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../logic/SourceFailures.js" as SourceFailures
import "../logic/CodeFormat.js" as CodeFormat

/**
 * Claude and Codex rate-limit usage: 5-hour and weekly (7-day) percentages
 * and reset times, fetched by scripts/agent-usage.py (stdlib-only; talks to
 * Claude's OAuth usage endpoint and to `codex app-server` directly). One
 * refresh when the first view appears, then every 5 minutes (`refreshAge`). The script caches the last good
 * reading on disk and falls back to it on a failed or rate-limited call, so
 * a percent of -1 only shows up when there is no usable cache either (not
 * logged in, expired token, or reset time already passed); AgentsRings
 * renders that as an empty ring and a "--" caption. Countdown captions are
 * recomputed every minute so they tick down live. The timers run only while
 * a view is visible (`viewers` > 0, see WhileVisible.qml). When the first
 * viewer appears, the clock and the readings are refreshed at once.
 * A failed read (no output, or output that is not the expected data) keeps the
 * last reading and writes one line to the shell log. The next line comes at
 * the earliest one hour later (SourceFailures.PERIOD_MS), however many
 * refreshes fail. The line names the source and a fixed reason only.
 */
Singleton {
    id: root

    property real claudeSessionPercent: -1
    property string claudeSessionResetAt: ""
    property real claudeWeeklyPercent: -1
    property string claudeWeeklyResetAt: ""

    property real codexSessionPercent: -1
    property string codexSessionResetAt: ""
    property real codexWeeklyPercent: -1
    property string codexWeeklyResetAt: ""
    property string claudeFetchedAt: ""
    property string codexFetchedAt: ""

    /** Time in milliseconds between two refreshes while a view shows. */
    readonly property int refreshAge: 5 * 60 * 1000

    /** Time in milliseconds that the script reuses a reading. The script reports it as `cacheSeconds` in each answer. */
    property int cacheAge: 0

    /**
     * Time in milliseconds that a reading counts as fresh. A refresh can return a reading that is almost one
     * cache time old, and the next refresh is one refresh period later, so a good reading reaches that age
     * before the script fetches a new one. The second refresh period is margin for the run time of the script.
     */
    readonly property int sourceAge: cacheAge + 2 * refreshAge
    readonly property bool claudeFresh: CodeFormat.sourceFresh(claudeFetchedAt, now, sourceAge)
    readonly property bool codexFresh: CodeFormat.sourceFresh(codexFetchedAt, now, sourceAge)
    readonly property real claudeSessionValue: CodeFormat.limitPercent(claudeSessionPercent, claudeSessionResetAt, now, claudeFresh)
    readonly property real claudeWeeklyValue: CodeFormat.limitPercent(claudeWeeklyPercent, claudeWeeklyResetAt, now, claudeFresh)
    readonly property real codexSessionValue: CodeFormat.limitPercent(codexSessionPercent, codexSessionResetAt, now, codexFresh)
    readonly property real codexWeeklyValue: CodeFormat.limitPercent(codexWeeklyPercent, codexWeeklyResetAt, now, codexFresh)

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    /** Ticks every minute purely to re-evaluate the countdown labels below. */
    property date now: new Date()

    readonly property string scriptPath: Quickshell.shellPath("scripts/agent-usage.py")

    readonly property string claudeSessionLabel: sessionCountdown(claudeSessionResetAt)
    readonly property string codexSessionLabel: sessionCountdown(codexSessionResetAt)
    readonly property string weeklyLabel: weeklyCountdown(claudeWeeklyResetAt) + " · " + weeklyCountdown(codexWeeklyResetAt)

    /** 0-100 for the ring; missing data (-1) draws as an empty ring. */
    function ringValue(percent) {
        return percent >= 0 ? percent : 0;
    }

    /** "2H 14M" when over an hour left, "42M" under an hour, "--" if unknown/passed. */
    function sessionCountdown(resetAt) {
        if (!resetAt) return "--";
        var ms = new Date(resetAt).getTime() - root.now.getTime();
        if (!(ms > 0)) return "--";
        var totalMin = Math.ceil(ms / 60000);
        var h = Math.floor(totalMin / 60);
        var m = totalMin % 60;
        return h > 0 ? (h + "H " + m + "M") : (m + "M");
    }

    /** "3D" when over a day left, "14H" under a day, "--" if unknown/passed. */
    function weeklyCountdown(resetAt) {
        if (!resetAt) return "--";
        var ms = new Date(resetAt).getTime() - root.now.getTime();
        if (!(ms > 0)) return "--";
        var totalHour = Math.ceil(ms / 3600000);
        var d = Math.floor(totalHour / 24);
        var h = totalHour % 24;
        return d > 0 ? (d + "D") : (h + "H");
    }

    /** True after the last view hid and stopped a run. That run ends with no output, which is not a failure to log. */
    property bool stoppedOnHide: false

    /** Last log line time of each source (see SourceFailures.js). */
    property var lastLogged: ({})

    /** Writes the failure line of a source unless it already wrote one in this period. */
    function logFailure(reason) {
        var line = SourceFailures.report(root.lastLogged, "usage", reason, Date.now());
        if (line !== "") console.warn(line);
    }

    function refresh() {
        if (fetchProcess.running) return;
        root.stoppedOnHide = false;
        fetchProcess.running = true;
    }

    function applyBucket(bucket, percentSetter, resetSetter) {
        if (bucket && typeof bucket.percent === "number") {
            percentSetter(bucket.percent);
            resetSetter(String(bucket.resetsAt || ""));
        } else {
            percentSetter(-1);
            resetSetter("");
        }
    }

    Process {
        id: fetchProcess
        command: ["python3", root.scriptPath]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (typeof data.cacheSeconds !== "number" || !(data.cacheSeconds > 0))
                        throw new Error("Missing cache time");
                    var claude = data.claude || {};
                    var codex = data.codex || {};
                    // The script fetched after the last clock tick, so freshness must be read at the arrival time.
                    root.now = new Date();
                    root.cacheAge = data.cacheSeconds * 1000;
                    root.claudeFetchedAt = String(claude.fetchedAt || "");
                    root.codexFetchedAt = String(codex.fetchedAt || "");
                    root.applyBucket(claude.session, function (p) { root.claudeSessionPercent = p; }, function (r) { root.claudeSessionResetAt = r; });
                    root.applyBucket(claude.weekly, function (p) { root.claudeWeeklyPercent = p; }, function (r) { root.claudeWeeklyResetAt = r; });
                    root.applyBucket(codex.session, function (p) { root.codexSessionPercent = p; }, function (r) { root.codexSessionResetAt = r; });
                    root.applyBucket(codex.weekly, function (p) { root.codexWeeklyPercent = p; }, function (r) { root.codexWeeklyResetAt = r; });
                } catch (e) {
                    // Malformed/empty output: keep the previous reading and log once per period.
                    if (!root.stoppedOnHide) root.logFailure(SourceFailures.outputReason(text));
                }
            }
        }
    }

    onViewersChanged: {
        if (viewers === 1) {
            now = new Date();
            refresh();
        } else if (viewers === 0 && fetchProcess.running) {
            root.stoppedOnHide = true;
            fetchProcess.running = false;
        }
    }

    Timer {
        interval: 60000
        running: root.viewers > 0
        repeat: true
        onTriggered: root.now = new Date()
    }

    Timer {
        interval: root.refreshAge
        running: root.viewers > 0
        repeat: true
        onTriggered: root.refresh()
    }
}
