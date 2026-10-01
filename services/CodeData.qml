pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Data of the Code tab. Token totals and estimated costs (tokens times list prices in data/model-prices.json) come from scripts/code-stats.py (local
 * Claude and Codex logs, cached 10 minutes); the contribution
 * calendar comes from scripts/github-stats.py (GitHub CLI, cached 30
 * minutes); commits come from scripts/local-commits.py (local git folders
 * merged with the GitHub commits, cached 10 minutes). All scripts answer from their disk cache when it is fresh, so
 * refresh() is cheap. Each open CodeTab calls watch() while it is visible;
 * the timer only runs while at least one tab is watching. Limits are not
 * here: the tab reads them from AgentUsage.
 */
Singleton {
    id: root

    /** Seven items, oldest first: { date: "YYYY-MM-DD", claude: int, codex: int }. */
    property var days: []

    /** This week's tokens per model, largest first: { claude: [{name, tokens}], codex: [...] }. */
    property var models: ({ claude: [], codex: [] })

    /** Tokens and estimated cost per agent and period: { claude: { today: {tokens, cost}, week: {...}, month: {...} }, codex: {...} }. */
    property var usage: ({})

    /** Contribution calendar of the last 12 months, oldest first: [["YYYY-MM-DD", count], ...]. */
    property var calendar: []
    property int calendarTotal: 0

    /** Contributions of every year, newest first: { year, total, days } (see scripts/github-stats.py). */
    property var calendarYears: []

    /** The 5 newest commits of the user (local folders and GitHub): { sha, message, repo, date }. */
    property var commits: []

    /** Ticks every minute so "12m ago" captions stay right. */
    property date now: new Date()

    /** Number of tabs that are visible now. */
    property int watchers: 0

    function scriptPath(name) {
        return Quickshell.shellPath("scripts/" + name);
    }

    /** A tab calls this with true when it shows and with false when it hides. */
    function watch(on) {
        root.watchers = Math.max(0, root.watchers + (on ? 1 : -1));
        if (on) root.refresh();
    }

    function refresh() {
        root.now = new Date();
        if (!statsProcess.running) statsProcess.running = true;
        if (!githubProcess.running) githubProcess.running = true;
    }

    /** Sets a property only when the value changed, so views do not rebuild for equal data. */
    function assign(name, value) {
        if (JSON.stringify(root[name]) !== JSON.stringify(value)) root[name] = value;
    }

    Process {
        id: statsProcess
        command: ["python3", root.scriptPath("code-stats.py")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    root.assign("days", data.days);
                    root.assign("models", data.models);
                    root.assign("usage", data.usage || {});
                } catch (e) {
                    // Empty or bad output: keep what the tab shows now.
                }
            }
        }
    }

    Process {
        id: githubProcess
        command: ["python3", root.scriptPath("github-stats.py")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    root.assign("calendar", data.days);
                    root.calendarTotal = data.total;
                    root.assign("calendarYears", data.years || []);
                } catch (e) {
                    // Offline with no cache: keep what the tab shows now.
                }
                // Commits merge the GitHub cache, so they run after it.
                if (!commitsProcess.running) commitsProcess.running = true;
            }
        }
    }

    Process {
        id: commitsProcess
        command: ["python3", root.scriptPath("local-commits.py")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.assign("commits", JSON.parse(text));
                } catch (e) {
                    // Empty or bad output: keep what the tab shows now.
                }
            }
        }
    }

    Timer {
        interval: 60000
        running: root.watchers > 0
        repeat: true
        onTriggered: {
            root.now = new Date();
            root.refresh();
        }
    }
}
