import QtQuick
import "../../logic/CodeFormat.js" as Fmt
import qs.common
import qs.services

/**
 * Tokens of the last 7 days, one column per day, stacked Claude (bottom)
 * over Codex (mock 5C "7 DAYS"). Hovering a day dims the others and shows
 * that day's total in the readout line.
 */
Rectangle {
    id: root

    /** Seven items, oldest first: { date: "YYYY-MM-DD", claude: int, codex: int }. */
    property var days: []
    property date now: new Date()

    readonly property color claudeTone: Theme.accentLight
    readonly property color codexTone: Theme.accentSecondary

    property int hoveredDay: -1

    readonly property real peak: {
        var m = 1;
        for (var i = 0; i < days.length; i++) m = Math.max(m, days[i].claude + days[i].codex);
        return m;
    }

    readonly property string readout: {
        if (days.length === 0) return "";
        if (hoveredDay >= 0 && hoveredDay < days.length) {
            var d = days[hoveredDay];
            var when = hoveredDay === days.length - 1 ? "Today"
                : Fmt.WEEKDAYS[Fmt.localDate(d.date).getDay()] + " " + Fmt.MONTHS[Fmt.localDate(d.date).getMonth()] + " " + Fmt.localDate(d.date).getDate();
            return (when + " · " + Fmt.tokens(d.claude + d.codex) + " tokens").toUpperCase();
        }
        var sum = 0;
        for (var i = 0; i < days.length; i++) sum += days[i].claude + days[i].codex;
        return ("7 days · " + Fmt.tokens(sum) + " tokens").toUpperCase();
    }

    color: Theme.card

    SideLabel {
        width: size
        textX: (width - lineHeight) / 2
        x: 10
        y: 10
        text: "7 DAYS"
    }

    Item {
        x: 29
        y: 10
        width: parent.width - 29 - 14
        height: parent.height - 20

        MonoText {
            id: readoutText
            y: 0
            text: root.readout
            color: root.hoveredDay >= 0 ? Theme.fg : Theme.dim
            font.letterSpacing: 0.54
            ColorFade on color {}
        }

        Row {
            anchors.right: parent.right
            spacing: 10
            MonoText { text: "CLAUDE"; color: root.claudeTone; font.letterSpacing: 0.54 }
            MonoText { text: "CODEX"; color: root.codexTone; font.letterSpacing: 0.54 }
        }

        Item {
            id: chart
            y: 16
            width: parent.width
            height: parent.height - y

            readonly property real slotWidth: (width - 6) / 7
            readonly property real barHeight: height - 5 - 9

            Repeater {
                model: root.days

                Item {
                    id: column
                    required property var modelData
                    required property int index

                    // Animated shares (0..1) of the bar area. Heights follow the live
                    // layout size, so a resize never leaves a bar taller than its cell.
                    // Bars start at 0 and rise once the delegate and the peak are settled.
                    property bool settled: false
                    Component.onCompleted: Qt.callLater(() => column.settled = true)
                    property real claudeShare: settled && root.peak > 0 ? Math.min(1, modelData.claude / root.peak) : 0
                    property real codexShare: settled && root.peak > 0 ? Math.min(1, modelData.codex / root.peak) : 0
                    Behavior on claudeShare { NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve } }
                    Behavior on codexShare { NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve } }
                    readonly property real claudeH: Math.max(0, Math.min(chart.barHeight, claudeShare * chart.barHeight))
                    readonly property real codexH: Math.max(0, Math.min(chart.barHeight - claudeH, codexShare * chart.barHeight))
                    readonly property bool today: index === root.days.length - 1

                    x: index * (chart.slotWidth + 1)
                    width: chart.slotWidth
                    height: chart.height
                    opacity: root.hoveredDay < 0 || root.hoveredDay === index ? 1 : 0.4
                    Fade on opacity {}

                    // The cell: bars are clipped to it at every frame.
                    Rectangle {
                        width: parent.width
                        height: Math.max(0, chart.barHeight)
                        color: Theme.sunk
                        clip: true

                        Rectangle {
                            id: claudeBar
                            width: parent.width
                            height: column.claudeH
                            y: parent.height - height
                            color: root.claudeTone
                        }

                        Rectangle {
                            width: parent.width
                            height: column.codexH
                            y: claudeBar.y - height - (column.claudeH > 0 && column.codexH > 0 ? 1 : 0)
                            color: root.codexTone
                        }
                    }

                    MonoText {
                        y: chart.barHeight + 5
                        height: 9
                        verticalAlignment: Text.AlignVCenter
                        text: (column.today ? "Today" : Fmt.WEEKDAYS[Fmt.localDate(column.modelData.date).getDay()]).toUpperCase()
                        color: column.today ? Theme.accentLight : Theme.dim
                    }

                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) root.hoveredDay = column.index;
                            else if (root.hoveredDay === column.index) root.hoveredDay = -1;
                        }
                    }
                }
            }
        }
    }
}
