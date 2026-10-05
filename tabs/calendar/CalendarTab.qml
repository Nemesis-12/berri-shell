import QtQuick
import QtQuick.Dialogs
import Quickshell
import "../../logic/Times.js" as Times
import qs.common
import qs.picker
import qs.services

/**
 * Calendar tab body (mock 5C SPINE, Berri Calendar v2.dc.html): month
 * card on the left (434px wide) and the day panel on the right (CalendarDayPanel). 1px gaps show the Theme.border
 * backdrop.
 *
 * Month changes crossfade between two grid pages with one progress value.
 * CALS flips the month grid into the calendars view (CalendarSourcesView) with
 * the same kind of crossfade: one straight-line phase, so the way back is the
 * way there played backwards.
 */
Item {
    id: root

    /** Day the user picked; the day panel shows this day. */
    property date selectedDate: new Date()

    /** 24-hour times in the day list. A settings page can change it. */
    property bool clock24: false

    /** Forwarded from the day panel: NEW pressed, or a row clicked. The details form opens on both. */
    signal newRequested
    signal itemClicked(string uid, string occurrenceDate)

    /** Set by the panel: true while it is open. Text fields give up focus when it closes. */
    property bool panelOpen: true

    /** True while a field of the details form or the link box has keyboard focus. The panel window asks for keyboard input only then. */
    readonly property bool textEntryActive: detailsForm.textEntryActive || sourcesView.textEntryActive

    /** What this tab asks of the panel: keyboard focus while a field is typed into, and the panel closed before the import dialog. */
    readonly property PanelRequests requests: PanelRequests {
        wantsKeyboard: root.textEntryActive
    }

    /** True while the calendars view is shown in place of the month grid. */
    property bool showCalendars: false
    property string saveError: ""

    WhileVisible { service: Calendar; counter: "saveErrorViewers"; when: root.panelOpen }

    Connections {
        target: Calendar
        function onSaveFailed(message) { root.saveError = message; }
        function onRevisionChanged() {
            if (Calendar.lastError === "") root.saveError = "";
        }
    }

    /** Closes the panel first (the file dialog would open under the panel's Overlay window), then opens the file dialog at rest. */
    function requestImport() {
        root.requests.dialogRequested(() => root.chooseImportFile(), true);
    }

    /** First weekday column: 1 = Monday, 0 = Sunday. A settings page can change it. */
    property int weekStart: 1

    /** Month shown: full year and month number 0..11. */
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    /** Day text of `today` at the last close; "" until the panel closes once. */
    property string closedDay: ""

    // Reopening on a later day selects the current day.
    onPanelOpenChanged: {
        if (!root.panelOpen) {
            sourcesView.releaseFocus();
            root.closedDay = Times.dayKey(root.today);
        } else if (root.closedDay !== "" && Times.dayKey(root.today) !== root.closedDay) {
            root.today_();
        }
    }

    // ---- calendars view (flip with the month grid)

    /** 0 = month grid, 1 = calendars view, in a straight line. Only showCalendars sets it. */
    property real flipPhase: root.showCalendars ? 1 : 0

    Behavior on flipPhase {
        NumberAnimation { duration: 240; easing.type: Easing.Linear }
    }

    readonly property real flipProgress: Theme.easeOut(root.flipPhase)

    function toggleCalendars() {
        sourcesView.reset();
        root.showCalendars = !root.showCalendars;
    }

    // ---- file chooser for IMPORT FILE

    /** Opens the file dialog (the host calls this once the panel is closed). */
    function chooseImportFile() {
        picker.open();
    }

    ImagePicker {
        id: picker
        dialogTitle: "Import Calendar"
        nameFilters: ["Calendar files (*.ics)"]
        startDir: (Quickshell.env("HOME") || "") + "/Downloads"
        fallbackDir: Quickshell.env("HOME") || ""
        onChosen: path => sourcesView.importPicked(path)
        // The panel reopens on the calendars view.
        onFinished: {
            root.showCalendars = true;
            root.requests.reopenRequested();
        }
    }

    function dayOf(key: string): date {
        return new Date(+key.slice(0, 4), +key.slice(5, 7) - 1, +key.slice(8, 10));
    }

    // A click outside the link box takes keyboard focus away from it.
    TapHandler {
        gesturePolicy: TapHandler.WithinBounds
        onTapped: eventPoint => {
            if (!sourcesView.linkContains(eventPoint.scenePosition)) sourcesView.releaseFocus();
        }
    }

    // Double-click on a day: select it and open a blank form there.
    function addOn(day) {
        root.pick(day);
        detailsForm.openNew(day);
    }

    // ---- Drag an item onto a day (mock: drag any chip or row, drop on a day cell)

    readonly property var frontGrid: root.frontIsA ? gridA : gridB
    property bool dragging: false
    property string dragUid: ""
    property string dragOccurrenceDate: ""
    property string dragFromKey: ""
    property point dragGrab
    property point dragOrigin
    /** Day text of the cell under the pointer, or "". */
    property string overKey: ""

    function beginDrag(info) {
        settle.stop();
        root.dragging = true;
        root.dragUid = info.uid;
        root.dragOccurrenceDate = info.occurrenceDate;
        root.dragFromKey = info.fromKey;
        root.dragGrab = info.grab;
        root.dragOrigin = root.mapFromItem(null, info.origin.x, info.origin.y);
        ghost.info = info;
        ghost.opacity = 0.8;
        ghost.width = info.width;
        ghost.height = info.height;
        root.moveDrag(root.mapToItem(null, root.dragOrigin.x + info.grab.x, root.dragOrigin.y + info.grab.y));
    }

    // The ghost follows the pointer: set here and nowhere else, whole pixels.
    function moveDrag(scenePoint) {
        var p = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        ghost.x = Math.round(p.x - root.dragGrab.x);
        ghost.y = Math.round(p.y - root.dragGrab.y);
        var day = root.frontGrid.dayAtScene(scenePoint);
        root.overKey = day ? Times.dayKey(day) : "";
    }

    // Drop on another day: the item moves (a repeating item: only that day) and the ghost flies into the cell. Anywhere else: the ghost flies back.
    function endDrag(scenePoint) {
        root.moveDrag(scenePoint);
        var day = root.frontGrid.dayAtScene(scenePoint);
        var target = null;
        if (day && Times.dayKey(day) !== root.dragFromKey) {
            if (day.getMonth() === root.viewMonth && day.getFullYear() === root.viewYear) {
                var corner = root.frontGrid.cellOriginOnScene(day);
                if (corner) target = root.mapFromItem(null, corner.x, corner.y);
            }
            if (Calendar.move(root.dragUid, root.dragOccurrenceDate, Times.dayKey(day))) root.pick(day);
            else target = null;
            // Into the chip slot of the cell (6px left, 5px number row and gap above).
            settleX.to = target ? target.x + 6 : root.dragOrigin.x;
            settleY.to = target ? target.y + 24 : root.dragOrigin.y;
        } else {
            settleX.to = root.dragOrigin.x;
            settleY.to = root.dragOrigin.y;
        }
        root.overKey = "";
        root.dragging = false;
        settle.restart();
    }

    function abortDrag() {
        root.overKey = "";
        root.dragging = false;
        settleX.to = root.dragOrigin.x;
        settleY.to = root.dragOrigin.y;
        settle.restart();
    }

    // The shared minute clock updates today at midnight and when the view opens.
    readonly property date today: Clock.minute

    WhileVisible { service: Clock }
    WhileVisible { service: Calendar }

    // Shows the month that contains `day` and selects it.
    function pick(day) {
        root.selectedDate = day;
        root.showMonth(day.getFullYear(), day.getMonth());
    }

    function showMonth(year, month) {
        var target = new Date(year, month, 1);
        year = target.getFullYear();
        month = target.getMonth();
        if (year === root.viewYear && month === root.viewMonth) return;
        var forward = year * 12 + month > root.viewYear * 12 + root.viewMonth;
        root.slideSign = forward ? 1 : -1;
        root.viewYear = year;
        root.viewMonth = month;
        // The page that was hidden takes the new month; roles swap.
        var incoming = root.frontIsA ? gridB : gridA;
        incoming.year = year;
        incoming.month = month;
        root.frontIsA = !root.frontIsA;
        fade.restart();
    }

    // A click on a chip selects its day and opens the item (as a click on a list row).
    function openItem(day, uid, occurrenceDate) {
        root.pick(day);
        root.itemClicked(uid, occurrenceDate);
        detailsForm.openEdit(uid, occurrenceDate);
    }

    function today_() {
        root.selectedDate = root.today;
        root.showMonth(root.today.getFullYear(), root.today.getMonth());
    }

    // Slide direction of the last month change: 1 forward, -1 back.
    property int slideSign: 1
    property bool frontIsA: true

    /** 0 = old page fully shown, 1 = new page fully shown. */
    property real progress: 1

    StandardMotion {
        id: fade
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 240
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    Item {
        id: monthCard
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 434

        // Title row: month, year, previous, today, next.
        Item {
            id: titleRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56

            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: prevButton.left
                anchors.rightMargin: 1
                color: Theme.card
                topLeftRadius: 7

                // Both texts sit in boxes as tall as their CSS line (34px and 10px) and are centered in the row.
                Item {
                    id: monthBox
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: monthText.implicitWidth
                    height: 34

                    Text {
                        textFormat: Text.PlainText
                        id: monthText
                        anchors.verticalCenter: parent.verticalCenter
                        text: Times.monthsLong[root.viewMonth].toUpperCase()
                        font.family: Theme.condensed
                        font.pixelSize: 34
                        font.weight: Font.Medium
                        font.letterSpacing: -0.68
                        color: Theme.fg
                    }
                }

                Item {
                    x: monthBox.x + monthBox.width + 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: yearText.implicitWidth
                    height: 10

                    MonoText {
                        id: yearText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.viewYear
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.letterSpacing: 1.2
                        color: Theme.dim
                    }
                }
            }

            // Month navigation with the same label and icon measurements.
            component HeaderButton: HoverButton {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                fill: Theme.card
                hoverFill: Theme.raised
                textColor: Theme.fg2
                hoverTextColor: Theme.fg2
                fontSize: 10
                letterSpacing: 1.4
                iconSize: 17
                iconStrokeWidth: 1.6
            }

            HeaderButton {
                id: prevButton
                anchors.right: todayButton.left
                anchors.rightMargin: 1
                width: 48
                icon: "chevron-left"
                onClicked: root.showMonth(root.viewYear, root.viewMonth - 1)
            }

            HeaderButton {
                id: todayButton
                anchors.right: nextButton.left
                anchors.rightMargin: 1
                width: todayMetrics.implicitWidth + 28
                label: "TODAY"
                onClicked: root.today_()

                MonoText {
                    id: todayMetrics
                    visible: false
                    text: "TODAY"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.letterSpacing: 1.4
                }
            }

            HeaderButton {
                id: nextButton
                anchors.right: parent.right
                width: 48
                icon: "chevron-right"
                onClicked: root.showMonth(root.viewYear, root.viewMonth + 1)
            }
        }

        // Month grid (weekday header and two pages). Fades out and moves up while the calendars view flips in.
        Item {
            id: gridArea
            anchors.top: titleRow.bottom
            anchors.topMargin: 1
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.flipProgress < 1
            enabled: root.flipProgress === 0
            opacity: 1 - root.flipProgress
            transform: Translate { y: -10 * root.flipProgress }

            // Weekday header.
            Item {
                id: weekdayRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 22

                Repeater {
                    model: 7

                    delegate: Rectangle {
                        required property int index

                        x: index * ((weekdayRow.width - 6) / 7 + 1)
                        width: (weekdayRow.width - 6) / 7
                        height: parent.height
                        color: Theme.sunk

                        MonoText {
                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            text: Times.weekdaysShort[(index + root.weekStart) % 7].toUpperCase()
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            font.letterSpacing: 1.26
                            color: Theme.dim
                        }
                    }
                }
            }

            // Two month pages; the front one shows the current month. Their month is set by showMonth(), not bound, so the outgoing page keeps its old month while it fades.
            Item {
                id: gridHost
                anchors.top: weekdayRow.bottom
                anchors.topMargin: 1
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true

                CalendarMonthGrid {
                    id: gridA
                    anchors.fill: parent
                    year: new Date().getFullYear()
                    month: new Date().getMonth()
                    weekStart: root.weekStart
                    selectedDate: root.selectedDate
                    today: root.today
                    opacity: root.frontIsA ? root.progress : 1 - root.progress
                    visible: opacity > 0.001
                    transform: Translate { y: 10 * root.slideSign * (root.frontIsA ? 1 - root.progress : -root.progress) }
                    z: root.frontIsA ? 1 : 0
                    enabled: root.frontIsA
                    dropKey: root.frontIsA ? root.overKey : ""
                    onDayPicked: day => root.pick(day)
                    onDayAddRequested: day => root.addOn(day)
                    onItemPicked: (day, uid, occurrenceDate) => root.openItem(day, uid, occurrenceDate)
                    onDragStarted: info => root.beginDrag(info)
                    onDragMoved: scenePoint => root.moveDrag(scenePoint)
                    onDragFinished: scenePoint => root.endDrag(scenePoint)
                    onDragAborted: root.abortDrag()
                }

                CalendarMonthGrid {
                    id: gridB
                    anchors.fill: parent
                    year: new Date().getFullYear()
                    month: new Date().getMonth()
                    weekStart: root.weekStart
                    selectedDate: root.selectedDate
                    today: root.today
                    opacity: root.frontIsA ? 1 - root.progress : root.progress
                    visible: opacity > 0.001
                    transform: Translate { y: 10 * root.slideSign * (root.frontIsA ? -root.progress : 1 - root.progress) }
                    z: root.frontIsA ? 0 : 1
                    enabled: !root.frontIsA
                    dropKey: root.frontIsA ? "" : root.overKey
                    onDayPicked: day => root.pick(day)
                    onDayAddRequested: day => root.addOn(day)
                    onItemPicked: (day, uid, occurrenceDate) => root.openItem(day, uid, occurrenceDate)
                    onDragStarted: info => root.beginDrag(info)
                    onDragMoved: scenePoint => root.moveDrag(scenePoint)
                    onDragFinished: scenePoint => root.endDrag(scenePoint)
                    onDragAborted: root.abortDrag()
                }
            }
        }

        // Calendars view: list of calendars and the link box.
        CalendarSourcesView {
            id: sourcesView
            anchors.top: titleRow.bottom
            anchors.topMargin: 1
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.flipProgress > 0
            enabled: root.flipProgress === 1
            opacity: root.flipProgress
            transform: Translate { y: 10 * (1 - root.flipProgress) }
            onImportRequested: root.requestImport()
        }
    }

    // Day panel: the selected day's list.
    CalendarDayPanel {
        id: dayPanel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: monthCard.right
        anchors.leftMargin: 1
        selectedDate: root.selectedDate
        clock24: root.clock24
        onNewRequested: {
            root.newRequested();
            detailsForm.openNew(root.selectedDate);
        }
        calendarsShown: root.showCalendars
        onCalendarsRequested: root.toggleCalendars()
        onDragStarted: info => root.beginDrag(info)
        onDragMoved: scenePoint => root.moveDrag(scenePoint)
        onDragFinished: scenePoint => root.endDrag(scenePoint)
        onDragAborted: root.abortDrag()
        onItemClicked: (uid, occurrenceDate) => {
            root.itemClicked(uid, occurrenceDate);
            detailsForm.openEdit(uid, occurrenceDate);
        }
    }

    // Details form: covers the day panel (NEW, double-click on a day, click on an item).
    CalendarDetailsForm {
        id: detailsForm
        anchors.fill: dayPanel
        panelOpen: root.panelOpen
        clock24: root.clock24
        onSaved: dateKey => root.pick(root.dayOf(dateKey))
    }

    // Drag ghost: a translucent copy of the chip or row, above everything.
    Item {
        id: ghost

        property var info: ({ shape: "chip", title: "", meta: "", done: false, tint: "white" })
        readonly property bool isRow: info.shape === "row"
        readonly property color tint: info.tint

        z: 100
        opacity: 0
        visible: opacity > 0
        enabled: false

        Rectangle {
            anchors.fill: parent
            color: ghost.isRow ? Theme.raised : Theme.card
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(ghost.tint.r, ghost.tint.g, ghost.tint.b, 0.15)
            visible: !ghost.isRow
        }

        Rectangle {
            width: 2
            height: parent.height
            color: ghost.tint
        }

        Text {
            textFormat: Text.PlainText
            x: ghost.isRow ? 14 : 6
            y: ghost.isRow ? 8 : Math.round((ghost.height - height) / 2)
            width: ghost.width - x - 6
            text: ghost.info.title
            elide: Text.ElideRight
            font.family: Theme.condensed
            font.pixelSize: ghost.isRow ? 14 : 10
            font.weight: Font.Medium
            font.strikeout: ghost.info.done
            color: ghost.info.done ? Theme.mute : (ghost.isRow ? Theme.fg : Theme.fg2)
        }

        MonoText {
            visible: ghost.isRow
            x: 14
            y: 8 + 14 + 4
            width: ghost.width - 20
            text: ghost.info.meta || ""
            elide: Text.ElideRight
            font.pixelSize: 9
            font.weight: Font.Medium
            font.letterSpacing: 0.36
            color: Theme.dim
        }
    }

    Rectangle {
        z: 200
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 36
        color: Theme.raised
        opacity: root.saveError !== "" ? 1 : 0
        visible: opacity > 0
        enabled: root.saveError !== ""
        Fade on opacity { duration: Theme.stateMs }

        Rectangle {
            width: 2
            height: parent.height
            color: CalendarColors.paletteColor("red", Theme.accent)
        }

        MonoText {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: dismissError.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.saveError
            elide: Text.ElideRight
            font.pixelSize: 10
            color: Theme.fg
        }

        HoverButton {
            id: dismissError
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            icon: "x"
            iconSize: 13
            onClicked: root.saveError = ""
        }
    }

    // Settle: move to the new cell or back to where it started, and fade. The ghost is a copy, so it fades while it arrives.
    ParallelAnimation {
        id: settle

        StandardMotion {
            id: settleX
            target: ghost
            property: "x"
            duration: 220
        }
        StandardMotion {
            id: settleY
            target: ghost
            property: "y"
            duration: 220
        }
        StandardMotion {
            target: ghost
            property: "opacity"
            to: 0
            duration: 220
        }
    }
}
