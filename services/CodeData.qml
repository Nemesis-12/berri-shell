pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Data of the Code tab. Token totals and estimated costs (tokens times list prices in data/model-prices.json) come from scripts/code-stats.py (local
 * Claude and Codex logs, cached 10 minutes); the contribution
 * calendar comes from scripts/github-stats.py (GitHub CLI, cached 30
 * minutes); commits come from scripts/local-commits.py (local git folders
 * merged with the GitHub commits, cached 10 minutes). Each open CodeTab calls
 * watch() while it is visible. The minute timer updates captions and checks
 * each source's age while at least one tab is watching. Limits are not
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

    property double statsCheckedAt: 0
    property double githubCheckedAt: 0
    property double commitsCheckedAt: 0
    property string statsVersion: ""
    property string githubVersion: ""
    property double commitsVersion: 0

    function scriptPath(name) {
        var s = String(Qt.resolvedUrl("../scripts/" + name));
        if (s.indexOf("file://") === 0) {
            s = s.substring(7);
            try { s = decodeURIComponent(s); } catch (e) {}
        }
        return s;
    }

    /** A tab calls this with true when it shows and with false when it hides. */
    function watch(on) {
        root.watchers = Math.max(0, root.watchers + (on ? 1 : -1));
        if (on) {
            root.now = new Date();
            root.checkFreshData();
        }
    }

    /** User request: run all sources now. The scripts can still use their disk caches. */
    function refresh() {
        root.now = new Date();
        root.startStats();
        root.startGithub();
    }

    function checkFreshData() {
        var time = Date.now();
        if (time - root.statsCheckedAt >= 10 * 60000) root.startStats();
        if (time - root.githubCheckedAt >= 30 * 60000) root.startGithub();
        else if (time - root.commitsCheckedAt >= 10 * 60000) root.startCommits();
    }

    // A fresh disk answer keeps its original age. Old offline answers wait one interval.
    function cacheAgeStart(savedAt, age) {
        var time = Date.now();
        return savedAt > time - age && savedAt <= time ? savedAt : time;
    }

    function startStats() {
        if (statsProcess.running) return;
        root.statsCheckedAt = Date.now();
        statsProcess.running = true;
    }

    function startGithub() {
        if (githubProcess.running) return;
        root.githubCheckedAt = Date.now();
        githubProcess.running = true;
    }

    function startCommits() {
        if (commitsProcess.running) return;
        root.commitsCheckedAt = Date.now();
        commitsProcess.running = true;
    }

    Process {
        id: statsProcess
        command: ["python3", root.scriptPath("code-stats.py")]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    root.statsCheckedAt = root.cacheAgeStart(Date.parse(data.generatedAt), 10 * 60000);
                    if (data.generatedAt !== root.statsVersion) {
                        root.statsVersion = data.generatedAt;
                        root.days = data.days;
                        root.models = data.models;
                        root.usage = data.usage || {};
                    }
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
                    root.githubCheckedAt = root.cacheAgeStart(Date.parse(data.fetchedAt), 30 * 60000);
                    if (data.fetchedAt !== root.githubVersion) {
                        root.githubVersion = data.fetchedAt;
                        root.calendar = data.days;
                        root.calendarTotal = data.total;
                        root.calendarYears = data.years || [];
                    }
                } catch (e) {
                    // Offline with no cache: keep what the tab shows now.
                }
                // Commits merge the GitHub cache, so they run after it.
                root.startCommits();
            }
        }
    }

    Process {
        id: commitsProcess
        command: ["python3", root.scriptPath("local-commits.py"), "--with-version"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    root.commitsCheckedAt = root.cacheAgeStart(data.version / 1000000, 10 * 60000);
                    if (data.version !== root.commitsVersion) {
                        root.commitsVersion = data.version;
                        root.commits = data.commits;
                    }
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
            root.checkFreshData();
        }
    }
}
