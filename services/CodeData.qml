pragma Singleton
import QtQuick
import Quickshell

/**
 * Data of the Code tab. Token totals and estimated costs (tokens times list prices in data/model-prices.json) come from scripts/code-stats.py (local
 * Claude and Codex logs, cached 10 minutes); the contribution
 * calendar comes from scripts/github-stats.py (GitHub CLI, cached 30
 * minutes); commits come from scripts/local-commits.py (local git folders
 * merged with the GitHub commits, cached 10 minutes). Each visible CodeTab counts
 * in `viewers` (see WhileVisible.qml). The minute timer updates captions. Each source
 * has its own refresh timer while at least one tab is visible. Limits are not
 * here: the tab reads them from AgentUsage.
 * Each source is one CachedSource, which owns its cache time, answer version,
 * timer and failure log line.
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

    /** How many Code tabs are visible now (see WhileVisible.qml). */
    property int viewers: 0

    /** Cache ages for local data and GitHub data. */
    readonly property int localAge: 10 * 60000
    readonly property int githubAge: 30 * 60000

    /** The first tab that shows starts the sources. The last tab that hides stops them. */
    onViewersChanged: {
        if (root.viewers === 1) {
            root.now = new Date();
            // GitHub starts before commits, so commits wait for it.
            stats.open();
            github.open();
            commitsSource.open();
        } else if (root.viewers === 0) {
            stats.close();
            github.close();
            commitsSource.close();
            // The tab is closed. Keep small summaries, but release the year grid and history.
            root.calendar = [];
            root.calendarYears = [];
            root.commits = [];
        }
    }

    /** A user request gets a new answer from every source. */
    function refresh() {
        root.now = new Date();
        stats.start(true);
        github.start(true);
        commitsSource.start(true);
    }

    CachedSource {
        id: stats
        name: "code stats"
        script: "code-stats.py"
        versionKey: "generatedAt"
        age: root.localAge
        keepWhenIdle: true
        onAnswered: data => {
            root.days = data.days;
            root.models = data.models;
            root.usage = data.usage || {};
        }
    }

    CachedSource {
        id: github
        name: "code github"
        script: "github-stats.py"
        versionKey: "fetchedAt"
        age: root.githubAge
        onAnswered: data => {
            root.calendar = data.days;
            root.calendarTotal = data.total;
            root.calendarYears = data.years || [];
        }
        // Commits include GitHub data, so rebuild them after its cache changes.
        onExited: if (root.viewers > 0) commitsSource.start(false)
    }

    CachedSource {
        id: commitsSource
        name: "code commits"
        script: "local-commits.py"
        args: ["--with-version"]
        versionKey: "version"
        age: root.localAge
        blocked: github.running
        onAnswered: data => root.commits = data.commits
    }

    Timer {
        interval: 60000
        running: root.viewers > 0
        repeat: true
        onTriggered: root.now = new Date()
    }
}
