import QtQuick
import "../../logic/CodeFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Code tab body (mock 5C SPINE, Berri Code v2.dc.html). Top row: the two
 * agent switch buttons, the Session and Weekly limit meters of the picked
 * agent, the stats column and the last commits. Middle row: tokens of the
 * last 7 days and tokens by model this week. Bottom: a year of GitHub
 * contributions. 1px gaps show the Theme.border backdrop.
 *
 * Limits come from AgentUsage; tokens and estimated costs from CodeData (local
 * logs times list prices); commits and contributions from CodeData (GitHub CLI).
 * The stats column shows tokens today, then the estimated cost of today, this
 * week and this month, each with that period's token total below it.
 */
Item {
    id: root

    WhileVisible { service: AgentUsage }
    WhileVisible { service: CodeData }

    /** Picked agent: "claude" or "codex". */
    property string agent: "claude"

    readonly property color agentTone: root.agent === "claude" ? Theme.accentLight : Theme.accentSecondary

    readonly property real sessionPercent: root.agent === "claude" ? AgentUsage.claudeSessionPercent : AgentUsage.codexSessionPercent
    readonly property real weeklyPercent: root.agent === "claude" ? AgentUsage.claudeWeeklyPercent : AgentUsage.codexWeeklyPercent
    readonly property string sessionResetAt: root.agent === "claude" ? AgentUsage.claudeSessionResetAt : AgentUsage.codexSessionResetAt
    readonly property string weeklyResetAt: root.agent === "claude" ? AgentUsage.claudeWeeklyResetAt : AgentUsage.codexWeeklyResetAt

    // Token figures of the picked agent.
    readonly property var agentDays: CodeData.days.map(d => d[root.agent])
    readonly property real todayTokens: agentDays.length > 0 ? agentDays[agentDays.length - 1] : 0
    // Tokens and estimated cost per period of the picked agent.
    readonly property var agentUsage: CodeData.usage[root.agent] || {}
    function periodTokens(period) { return agentUsage[period] ? agentUsage[period].tokens : 0; }
    function periodCost(period) { return agentUsage[period] ? agentUsage[period].cost : 0; }


    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // Top row.
    Item {
        id: topRow
        width: parent.width
        height: 200

        Column {
            width: 96
            height: parent.height
            spacing: 1

            Repeater {
                model: [{ id: "claude", label: "Claude" }, { id: "codex", label: "Codex" }]

                CodeAgentButton {
                    required property var modelData
                    width: 96
                    height: (topRow.height - 1) / 2
                    brand: modelData.id
                    label: modelData.label
                    selected: root.agent === modelData.id
                    onClicked: root.agent = modelData.id
                }
            }
        }

        CodeLimitMeter {
            x: 97
            width: 82
            height: parent.height
            name: "Session"
            percent: root.sessionPercent
            timeLeft: Fmt.timeLeft(new Date(root.sessionResetAt), AgentUsage.now).toUpperCase()
        }

        CodeLimitMeter {
            x: 180
            width: 82
            height: parent.height
            name: "Weekly"
            percent: root.weeklyPercent
            timeLeft: Fmt.timeLeft(new Date(root.weeklyResetAt), AgentUsage.now).toUpperCase()
        }

        Column {
            x: 263
            width: 140
            height: parent.height
            spacing: 1

            Repeater {
                model: [
                    { label: "TOKENS TODAY", value: Fmt.tokens(root.todayTokens), sub: "" },
                    { label: "COST TODAY", value: Fmt.cost(root.periodCost("today")), sub: Fmt.tokens(root.periodTokens("today")) + " tokens" },
                    { label: "COST THIS WEEK", value: Fmt.cost(root.periodCost("week")), sub: Fmt.tokens(root.periodTokens("week")) + " tokens" },
                    { label: "COST THIS MONTH", value: Fmt.cost(root.periodCost("month")), sub: Fmt.tokens(root.periodTokens("month")) + " tokens" }
                ]

                CodeStatCell {
                    required property var modelData
                    width: 140
                    height: (topRow.height - 3) / 4
                    label: modelData.label
                    value: modelData.value
                    sub: modelData.sub
                }
            }
        }

        CodeCommits {
            x: 404
            width: parent.width - x
            height: parent.height
            commits: CodeData.commits
            now: CodeData.now
        }
    }

    // Middle row.
    CodeDays {
        y: 201
        width: parent.width - 291
        height: 119
        days: CodeData.days
    }

    CodeModels {
        x: parent.width - 290
        y: 201
        width: 290
        height: 119
        rows: CodeData.models[root.agent] || []
        tone: root.agentTone
    }

    // Bottom row.
    CodeHeatmap {
        y: 321
        width: parent.width
        height: parent.height - y
        lastYear: CodeData.calendar
        lastYearTotal: CodeData.calendarTotal
        years: CodeData.calendarYears
    }
}
