import QtQuick
import "../../logic/CalendarDrag.js" as Drag
import "../../logic/Times.js" as Times
import qs.common
import qs.services

/**
 * One month page: 6 rows x 7 columns of day cells with 1px hairline gaps
 * (mock 5C SPINE month grid). Shows days from the previous and next month
 * dimmed. Each cell has its date number, up to as many item chips as fit
 * and "+N" for the rest. The parent shows two of these and crossfades them
 * when the month changes.
 *
 * Items come from the Calendar store: it is asked once per month shown
 * (previous, this, next) each time Calendar.revision changes, and not once
 * per cell. A hidden page does not ask. It builds again when it is shown.
 */
Item {
    id: root

    /** Month shown: full year and month number 0..11. */
    property int year: 2026
    property int month: 0

    /** First weekday column: 1 = Monday, 0 = Sunday. */
    property int weekStart: 1

    /** Day marked as selected, and the current day. Both are JS Dates. */
    property date selectedDate: new Date()
    property date today: new Date()

    /** Sent when the user clicks a day cell; the argument is that day. */
    signal dayPicked(date day)

    /** Sent on a double-click on a day cell (add an item there). */
    signal dayAddRequested(date day)

    /** Sent when the user clicks an item chip: its day, and the item. */
    signal itemPicked(date day, string uid, string occurrenceDate)

    /**
     * Drag of a chip (the tab draws the ghost). dragStarted carries the item
     * and the chip's look; the point arguments are scene positions.
     */
    signal dragStarted(var info)
    signal dragMoved(point scenePoint)
    signal dragFinished(point scenePoint)
    signal dragAborted

    /** Day text ("YYYY-MM-DD") of the cell that would take the drop, or "". */
    property string dropKey: ""

    readonly property int rows: 6
    readonly property int columns: 7
    readonly property real cellWidth: (width - (columns - 1)) / columns
    readonly property real cellHeight: (height - (rows - 1)) / rows
    readonly property int chipHeight: 14
    readonly property int chipGap: 3
    // Room under the 16px number row (5px padding top and bottom, 3px gap).
    readonly property int chipsThatFit: Math.max(0, Math.floor((cellHeight - 10 - 16) / (chipHeight + chipGap)))

    // Day cells: date, and the items of that day. A hidden page keeps its last cells and builds again when shown.
    property var cells: []
    property bool cellsStale: true

    function refreshCells(): void {
        if (!root.visible) { root.cellsStale = true; return; }
        root.cellsStale = false;
        var first = new Date(root.year, root.month, 1);
        var offset = (first.getDay() - root.weekStart + 7) % 7;
        // Calendar.itemsInMonth gives { "YYYY-MM-DD": [item] } for one month (months 1..12).
        var byDay = {};
        for (var m = -1; m <= 1; m++) {
            var shown = new Date(root.year, root.month + m, 1);
            var found = Calendar.itemsInMonth(shown.getFullYear(), shown.getMonth() + 1);
            for (var key in found) byDay[key] = found[key];
        }
        var firstDayNumber = Times.dayNum(Times.dayKey(first)) - offset;
        var out = [];
        for (var n = 0; n < 42; n++) {
            var dayKey = Times.keyOfDayNum(firstDayNumber + n);
            var day = new Date(dayKey + "T00:00:00");
            out.push({ date: day, items: byDay[dayKey] || [] });
        }
        root.cells = out;
    }

    onYearChanged: refreshCells()
    onMonthChanged: refreshCells()
    onWeekStartChanged: refreshCells()
    onVisibleChanged: if (visible && cellsStale) refreshCells()
    Component.onCompleted: refreshCells()

    Connections {
        target: Calendar
        function onRevisionChanged() { root.refreshCells(); }
    }

    /** The day under a scene point, or null when the point is outside the grid. */
    function dayAtScene(scenePoint): var {
        var p = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        if (p.x < 0 || p.y < 0 || p.x >= width || p.y >= height) return null;
        var column = Math.min(root.columns - 1, Math.floor(p.x / (root.cellWidth + 1)));
        var row = Math.min(root.rows - 1, Math.floor(p.y / (root.cellHeight + 1)));
        return root.cells[row * root.columns + column].date;
    }

    /** Top-left corner, in scene coordinates, of the cell that shows `day`, or null. */
    function cellOriginOnScene(day): var {
        for (var n = 0; n < root.cells.length; n++) {
            if (Times.dayKey(root.cells[n].date) !== Times.dayKey(day)) continue;
            return root.mapToItem(null, (n % root.columns) * (root.cellWidth + 1), Math.floor(n / root.columns) * (root.cellHeight + 1));
        }
        return null;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    Repeater {
        model: root.cells

        delegate: Rectangle {
            id: cell

            required property int index
            required property var modelData

            readonly property date day: modelData.date
            readonly property bool inMonth: day.getMonth() === root.month
            readonly property bool isToday: Times.dayKey(day) === Times.dayKey(root.today)
            readonly property bool isSelected: Times.dayKey(day) === Times.dayKey(root.selectedDate)
            readonly property int shown: Math.min(modelData.items.length, root.chipsThatFit)

            x: (index % root.columns) * (root.cellWidth + 1)
            y: Math.floor(index / root.columns) * (root.cellHeight + 1)
            width: root.cellWidth
            height: root.cellHeight
            clip: true
            readonly property bool isDropTarget: root.dropKey !== "" && root.dropKey === Times.dayKey(day)
            // Mock: the day under a dragged item takes the hover fill.
            color: isDropTarget ? Theme.hover : (isSelected ? Theme.selectionSoft : (inMonth ? Theme.card : Theme.shell))

            ColorFade on color { duration: Theme.stateMs }

            // Blank-cell click selects the day. It sits below the chips, so a chip gets its own clicks and drags.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dayPicked(cell.day)
                onDoubleClicked: root.dayAddRequested(cell.day)
            }

            HoverHandler { id: cellHover }

            Item {
                anchors.fill: parent
                anchors.topMargin: 5
                anchors.bottomMargin: 5
                anchors.leftMargin: 6
                anchors.rightMargin: 5

                Rectangle {
                    id: numberBox
                    width: Math.max(16, numberText.implicitWidth + 6)
                    height: 16
                    color: cell.isToday ? Theme.accent : "transparent"

                    ColorFade on color { duration: Theme.stateMs }

                    Text {
                        textFormat: Text.PlainText
                        id: numberText
                        anchors.centerIn: parent
                        text: cell.day.getDate()
                        font.family: Theme.condensed
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: cell.isToday ? Theme.onAccent : (cell.inMonth ? Theme.fg2 : Theme.mute)
                        ColorFade on color { duration: Theme.stateMs }
                    }
                }

                MonoText {
                    anchors.right: parent.right
                    anchors.verticalCenter: numberBox.verticalCenter
                    visible: cell.modelData.items.length > cell.shown
                    text: "+" + (cell.modelData.items.length - cell.shown)
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: Theme.dim
                }

                Column {
                    y: 16 + root.chipGap
                    width: parent.width
                    spacing: root.chipGap

                    Repeater {
                        model: cell.modelData.items.slice(0, cell.shown)

                        delegate: Rectangle {
                            id: chip

                            required property var modelData

                            readonly property color tint: CalendarColors.resolve(modelData.color)

                            width: parent.width
                            height: root.chipHeight
                            color: Qt.rgba(tint.r, tint.g, tint.b, cell.inMonth ? 0.15 : 0.08)
                            ColorFade on color { duration: Theme.stateMs }

                            Rectangle {
                                width: 2
                                height: parent.height
                                color: chip.tint
                            }

                            // Click opens the item. Press and move past the threshold drags it.
                            MouseArea {
                                id: chipMouse

                                property bool dragging: false
                                property bool moved: false
                                property point pressAt

                                anchors.fill: parent
                                cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                onPressed: mouse => {
                                    pressAt = Qt.point(mouse.x, mouse.y);
                                    moved = false;
                                    dragging = false;
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed || chip.modelData.readOnly) return;
                                    if (!dragging) {
                                        if (!Drag.pastThreshold(mouse.x - pressAt.x, mouse.y - pressAt.y)) return;
                                        dragging = true;
                                        moved = true;
                                        root.dragStarted({
                                            shape: "chip",
                                            fromKey: Times.dayKey(cell.day),
                                            uid: chip.modelData.uid,
                                            occurrenceDate: chip.modelData.occurrenceDate,
                                            title: chip.modelData.title,
                                            done: chip.modelData.done,
                                            tint: chip.tint,
                                            width: chip.width,
                                            height: chip.height,
                                            grab: pressAt,
                                            origin: chip.mapToItem(null, 0, 0)
                                        });
                                    }
                                    root.dragMoved(mapToItem(null, mouse.x, mouse.y));
                                }
                                onReleased: mouse => {
                                    if (!dragging) return;
                                    dragging = false;
                                    root.dragFinished(mapToItem(null, mouse.x, mouse.y));
                                }
                                onCanceled: {
                                    if (!dragging) return;
                                    dragging = false;
                                    root.dragAborted();
                                }
                                onClicked: if (!moved) root.itemPicked(cell.day, chip.modelData.uid, chip.modelData.occurrenceDate)
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.condensed
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                font.strikeout: chip.modelData.done
                                color: chip.modelData.done ? Theme.mute : (cell.inMonth ? Theme.fg2 : Theme.dim)
                                ColorFade on color { duration: Theme.stateMs }
                            }
                        }
                    }
                }
            }

            // Selected day: 2px accent top edge.
            Rectangle {
                width: parent.width
                height: 2
                color: Theme.accent
                opacity: cell.isSelected ? 1 : 0

                Fade on opacity { duration: Theme.stateMs }
            }

            // Hover brightening (mock: brightness 1.2).
            Rectangle {
                anchors.fill: parent
                color: Theme.fg
                opacity: cellHover.hovered ? 0.06 : 0

                Fade on opacity {}
            }
        }
    }
}
