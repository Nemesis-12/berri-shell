import QtQuick
import "../../logic/CodeFormat.js" as Fmt
import qs.common
import qs.services

/**
 * GitHub contributions (mock 5C): a header with a period switch, the total,
 * the current and best streak and a hover readout, then one square per day
 * in week columns (Sunday on top) with month names above. The switch steps
 * from the last 12 months back through every past year. Hovering a square
 * outlines it and shows its date and count.
 */
Rectangle {
    id: root

    /** Last 12 months: [["YYYY-MM-DD", count], ...] oldest first, starting on a Sunday. */
    property var lastYear: []
    property int lastYearTotal: 0

    /** Every year, newest first: { year, total, days } (days as above; count -1 pads the first week). */
    property var years: []

    // 0 is the last 12 months, n is years[n - 1]. `picked` is what the user chose;
    // `period` is what the grid shows now (it follows `picked` in the middle of the fade).
    property int picked: 0
    property int period: 0
    readonly property int periodCount: years.length + 1
    readonly property var calendar: period > 0 && period <= years.length ? years[period - 1].days : lastYear
    readonly property int total: period > 0 && period <= years.length ? years[period - 1].total : lastYearTotal
    readonly property string periodLabel: period > 0 && period <= years.length ? String(years[period - 1].year) : "12 MO"
    property real fade: 1

    onPickedChanged: swapAnimation.restart()
    onYearsChanged: if (picked >= periodCount) picked = 0

    // Fades the grid and totals out, swaps the period, fades them back in.
    SequentialAnimation {
        id: swapAnimation
        NumberAnimation { target: root; property: "fade"; to: 0; duration: Theme.stateMs / 2; easing.type: Easing.OutCubic }
        ScriptAction { script: { root.hoveredIndex = -1; root.period = root.picked; } }
        NumberAnimation { target: root; property: "fade"; to: 1; duration: Theme.stateMs / 2; easing.type: Easing.OutCubic }
    }

    readonly property int cell: 10
    readonly property int gap: 2
    readonly property int columns: Math.ceil(calendar.length / 7)

    property int hoveredIndex: -1

    // Level colors: none, then four steps toward the accent tone.
    readonly property var levelColors: [
        Theme.shell,
        Theme.oklabMix(Theme.accentLight, Theme.card, 28),
        Theme.oklabMix(Theme.accentLight, Theme.card, 52),
        Theme.oklabMix(Theme.accentLight, Theme.card, 76),
        Theme.accentLight
    ]

    // Current streak (today may still be empty) and best streak.
    readonly property var streaks: {
        var cur = 0, best = 0, run = 0;
        for (var i = 0; i < calendar.length; i++) {
            run = calendar[i][Fmt.CONTRIBUTION_COUNT] > 0 ? run + 1 : 0;
            best = Math.max(best, run);
        }
        var k = calendar.length - 1;
        if (k >= 0 && calendar[k][Fmt.CONTRIBUTION_COUNT] <= 0) k--;
        while (k >= 0 && calendar[k][Fmt.CONTRIBUTION_COUNT] > 0) { cur++; k--; }
        return { current: cur, best: best };
    }

    readonly property string readout: {
        if (hoveredIndex < 0 || hoveredIndex >= calendar.length) return "Hover a day".toUpperCase();
        var contributionDate = Fmt.localDate(calendar[hoveredIndex][Fmt.CONTRIBUTION_DATE]);
        var contributionCount = calendar[hoveredIndex][Fmt.CONTRIBUTION_COUNT];
        return (Fmt.WEEKDAYS[contributionDate.getDay()] + ", " + Fmt.MONTHS[contributionDate.getMonth()] + " " + contributionDate.getDate() + " · "
            + (contributionCount > 0 ? contributionCount + (contributionCount === 1 ? " contribution" : " contributions") : "No contributions")).toUpperCase();
    }

    color: Theme.card

    Item {
        x: 14
        y: 8
        width: parent.width - 28
        height: parent.height - 16

        // Header line.
        MonoText {
            id: githubLabel
            y: 2
            text: "GITHUB"
            font.letterSpacing: 1.26
        }

        // Period switch: the chevron on the left steps to an older period.
        Item {
            id: periodSwitch
            x: githubLabel.width + 12
            height: 14
            width: 14 + 34 + 14
            anchors.verticalCenter: githubLabel.verticalCenter

            Repeater {
                model: 2
                MouseArea {
                    required property int index
                    readonly property int step: index === 0 ? 1 : -1
                    readonly property bool usable: root.picked + step >= 0 && root.picked + step < root.periodCount
                    x: index === 0 ? 0 : 14 + 34
                    width: 14
                    height: 14
                    enabled: usable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked += step
                    Icon {
                        anchors.centerIn: parent
                        name: parent.index === 0 ? "chevron-left" : "chevron-right"
                        size: 12
                        strokeWidth: 2
                        color: parent.containsMouse ? Theme.fg : Theme.dim
                        opacity: parent.usable ? 1 : 0.3
                        ColorFade on color {}
                        Fade on opacity {}
                    }
                }
            }
            MonoText {
                x: 14
                width: 34
                height: parent.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.periodLabel
                color: Theme.accentLight
                font.letterSpacing: 0.54
                opacity: root.fade
            }
        }

        Item {
            id: totals
            x: periodSwitch.x + periodSwitch.width + 12
            width: totalText.width + 12 + streakText.width
            height: githubLabel.height
            y: githubLabel.y
            opacity: root.fade
            CondensedText {
                id: totalText
                anchors.verticalCenter: parent.verticalCenter
                text: root.total.toLocaleString(Qt.locale("en_US"), "f", 0) + " CONTRIBUTIONS"
            }
            MonoText {
                id: streakText
                x: totalText.width + 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.streaks.current + "-DAY STREAK · BEST " + root.streaks.best
                font.letterSpacing: 0.54
            }
        }
        MonoText {
            anchors.right: parent.right
            anchors.verticalCenter: githubLabel.verticalCenter
            text: root.readout
            color: root.hoveredIndex >= 0 ? Theme.fg : Theme.dim
            font.letterSpacing: 0.54
            ColorFade on color {}
        }

        // Weekday names, every other row.
        Column {
            y: 19 + 12
            spacing: root.gap
            Repeater {
                model: 7
                MonoText {
                    required property int index
                    width: 24
                    height: root.cell
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 8
                    text: index % 2 === 0 ? Fmt.WEEKDAYS[index].toUpperCase() : ""
                }
            }
        }

        Item {
            id: grid
            x: 30
            y: 19
            opacity: root.fade
            width: root.columns * (root.cell + root.gap) - root.gap
            height: 12 + 7 * (root.cell + root.gap) - root.gap

            // Month names over the first week column of each month.
            Repeater {
                model: root.columns
                MonoText {
                    required property int index
                    readonly property var first: root.calendar.length > index * 7 ? Fmt.localDate(root.calendar[index * 7][Fmt.CONTRIBUTION_DATE]) : null
                    x: index * (root.cell + root.gap)
                    height: 9
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 8
                    text: first && first.getDate() <= 7 ? Fmt.MONTHS[first.getMonth()].toUpperCase() : ""
                }
            }

            Repeater {
                model: root.calendar.length
                Rectangle {
                    required property int index
                    x: Math.floor(index / 7) * (root.cell + root.gap)
                    y: 12 + (index % 7) * (root.cell + root.gap)
                    width: root.cell
                    height: root.cell
                    visible: root.calendar[index][Fmt.CONTRIBUTION_COUNT] >= 0
                    color: root.levelColors[Fmt.heatLevel(root.calendar[index][Fmt.CONTRIBUTION_COUNT])]
                }
            }

            // Outline of the hovered square.
            Rectangle {
                readonly property int i: Math.max(0, root.hoveredIndex)
                x: Math.floor(i / 7) * (root.cell + root.gap)
                y: 12 + (i % 7) * (root.cell + root.gap)
                width: root.cell
                height: root.cell
                color: "transparent"
                border.width: 1.5
                border.color: Theme.fg
                opacity: root.hoveredIndex >= 0 ? 1 : 0
                Fade on opacity {}
            }

            HoverHandler {
                id: gridHover
                onPointChanged: {
                    var col = Math.floor(point.position.x / (root.cell + root.gap));
                    var row = Math.floor((point.position.y - 12) / (root.cell + root.gap));
                    var inX = point.position.x - col * (root.cell + root.gap) < root.cell;
                    var inY = point.position.y - 12 - row * (root.cell + root.gap) < root.cell;
                    var idx = col * 7 + row;
                    if (row >= 0 && row < 7 && inX && inY && idx < root.calendar.length && root.calendar[idx][Fmt.CONTRIBUTION_COUNT] >= 0) root.hoveredIndex = idx;
                }
                onHoveredChanged: if (!hovered) root.hoveredIndex = -1
            }
        }
    }
}
