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
 * watch() while it is visible. The minute timer updates captions. Each source
 * has its own refresh timer while at least one tab is watching. Limits are not
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

    /** Cache ages for local data and GitHub data. */
    readonly property int localAge: 10 * 60000
    readonly property int githubAge: 30 * 60000

    /** Start time of the current cache age for each source. */
    property double statsCheckedAt: 0
    property double githubCheckedAt: 0
    property double commitsCheckedAt: 0
    /** Last answer version shown by each source. */
    property string statsVersion: ""
    property string githubVersion: ""
    property double commitsVersion: 0
    /** Return the local path of a Code data script. */
    function scriptPath(name) {
        return Quickshell.shellPath("scripts/" + name);
    }

    /** A tab calls this with true when it shows and with false when it hides. */
    function watch(on) {
        root.watchers = Math.max(0, root.watchers + (on ? 1 : -1));
        if (on) {
            root.now = new Date();
            root.checkFreshData();
        } else if (root.watchers === 0) {
            statsTimer.stop();
            githubTimer.stop();
            commitsTimer.stop();
            // The tab is closed. Keep small summaries, but release the year grid and history.
            root.calendar = [];
            root.calendarYears = [];
            root.commits = [];
            root.githubCheckedAt = 0;
            root.commitsCheckedAt = 0;
            root.githubVersion = "";
            root.commitsVersion = 0;
        }
    }

    /** A user request gets a new answer from every source. */
    function refresh() {
        root.now = new Date();
        root.startStats(true);
        root.startGithub(true);
        root.startCommits(true);
    }

    /** Start old sources, or set their next timer from the saved answer age. */
    function checkFreshData() {
        root.checkSource(root.statsCheckedAt, root.localAge, statsTimer, root.startStats);
        root.checkSource(root.githubCheckedAt, root.githubAge, githubTimer, root.startGithub);
        if (!githubProcess.running)
            root.checkSource(root.commitsCheckedAt, root.localAge, commitsTimer, root.startCommits);
    }

    /** Start one old source or wait until its cache age ends. */
    function checkSource(checkedAt, age, timer, start) {
        if (root.watchers === 0) return;
        if (Date.now() - checkedAt >= age) start();
        else root.scheduleSource(timer, checkedAt, age);
    }

    /** Set a source timer to the time left in its cache age. */
    function scheduleSource(timer, checkedAt, age) {
        if (root.watchers === 0) return;
        timer.interval = Math.max(1, age - (Date.now() - checkedAt));
        timer.restart();
    }

    /** Keep a fresh disk answer's age; retry an old offline answer after one age. */
    function cacheAgeStart(savedAt, age) {
        var time = Date.now();
        return savedAt > time - age && savedAt <= time ? savedAt : time;
    }

    /** Ask the local statistics source for data. */
    function startStats(force) {
        if (statsProcess.running) return;
        statsTimer.stop();
        root.statsCheckedAt = Date.now();
        statsProcess.command = ["python3", root.scriptPath("code-stats.py")].concat(force ? ["--force"] : []);
        statsProcess.running = true;
    }

    /** Ask GitHub for contribution data. */
    function startGithub(force) {
        if (githubProcess.running) return;
        githubTimer.stop();
        root.githubCheckedAt = Date.now();
        githubProcess.command = ["python3", root.scriptPath("github-stats.py")].concat(force ? ["--force"] : []);
        githubProcess.running = true;
    }

    /** Ask the commits source for data. */
    function startCommits(force) {
        if (commitsProcess.running) return;
        commitsTimer.stop();
        root.commitsCheckedAt = Date.now();
        commitsProcess.command = ["python3", root.scriptPath("local-commits.py"), "--with-version"]
            .concat(force ? ["--force"] : []);
        commitsProcess.running = true;
    }

    Process {
        id: statsProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    root.statsCheckedAt = root.cacheAgeStart(Date.parse(data.generatedAt), root.localAge);
                    if (data.generatedAt !== root.statsVersion) {
                        root.statsVersion = data.generatedAt;
                        root.days = data.days;
                        root.models = data.models;
                        root.usage = data.usage || {};
                    }
                } catch (e) {
                    // Empty or bad output: keep what the tab shows now.
                }
                root.scheduleSource(statsTimer, root.statsCheckedAt, root.localAge);
            }
        }
    }

    Process {
        id: githubProcess
        onExited: {
            // Commits include GitHub data, so rebuild them after its cache changes.
            if (root.watchers > 0) root.startCommits();
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (root.watchers > 0) {
                        root.githubCheckedAt = root.cacheAgeStart(Date.parse(data.fetchedAt), root.githubAge);
                    }
                    if (root.watchers > 0 && data.fetchedAt !== root.githubVersion) {
                        root.githubVersion = data.fetchedAt;
                        root.calendar = data.days;
                        root.calendarTotal = data.total;
                        root.calendarYears = data.years || [];
                    }
                } catch (e) {
                    // Offline with no cache: keep what the tab shows now.
                }
                root.scheduleSource(githubTimer, root.githubCheckedAt, root.githubAge);
            }
        }
    }

    Process {
        id: commitsProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (root.watchers > 0) {
                        root.commitsCheckedAt = root.cacheAgeStart(data.version, root.localAge);
                    }
                    if (root.watchers > 0 && data.version !== root.commitsVersion) {
                        root.commitsVersion = data.version;
                        root.commits = data.commits;
                    }
                } catch (e) {
                    // Empty or bad output: keep what the tab shows now.
                }
                root.scheduleSource(commitsTimer, root.commitsCheckedAt, root.localAge);
            }
        }
    }

    Timer {
        interval: 60000
        running: root.watchers > 0
        repeat: true
        onTriggered: root.now = new Date()
    }

    Timer {
        id: statsTimer
        onTriggered: root.startStats()
    }

    Timer {
        id: githubTimer
        onTriggered: root.startGithub()
    }

    Timer {
        id: commitsTimer
        onTriggered: if (!githubProcess.running) root.startCommits()
    }
}
