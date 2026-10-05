import QtQuick
import "../../logic/CalendarItems.js" as Items
import "../../logic/CalendarQueries.js" as Queries
import "../../logic/ShownRows.js" as ShownRows
import qs.common
import qs.services

/**
 * Calendars view (mock 5C SPINE, Berri Calendar v2.dc.html, sources option C):
 * takes the place of the month grid. A header row (NAME, UPDATED), one
 * row per calendar, and at the bottom the link box with IMPORT FILE and
 * SUBSCRIBE and a live hint line.
 *
 * Rows: the color square opens a color popover for that calendar, the eye
 * shows or hides it, refresh is for links, remove is for files and links.
 * The square left of the link box shows the color the next calendar gets and
 * opens the same popover. The link box checks a typed link after a
 * short pause (Calendar.checkLink) and subscribes on Enter or SUBSCRIBE.
 * IMPORT FILE asks the host to close the panel and open the file dialog
 * (importRequested); the host calls importPicked(path) with the chosen file.
 */
Item {
    id: root

    /** True while the link box has keyboard focus. */
    readonly property bool textEntryActive: linkInput.textEntryActive || colorPopover.textEntryActive

    /** IMPORT FILE pressed. The host closes the panel, then opens the file dialog. */
    signal importRequested

    // Column layout: name 1fr, updated 88px, actions 76px (eye, refresh, remove), 8px gaps.
    readonly property real nameWidth: width - 12 - 6 - 88 - 76 - 2 * 8
    readonly property real updatedX: 12 + nameWidth + 8

    readonly property color redColor: CalendarColors.paletteColor("red", Theme.accent)

    // ---- color of the next calendar and the color popover

    /** Color the next imported or subscribed calendar gets (preset key or "#rrggbb"). */
    property string newColor: Calendar.nextCalendarColor()

    /** "" while the popover changes newColor, else the id of the calendar it changes. */
    property string popoverCalendarId: ""
    property real popoverX: 0
    property real popoverY: 0

    function colorOfCalendar(id: string): string {
        var found = (Calendar.calendars || []).filter(function (c) { return c.id === id; })[0];
        return found ? found.color : "accent";
    }

    /**
     * Opens the popover next to `anchor` (a color square). calendarId "" is the new-calendar square.
     * `edgeItem` is the box the popover must not cover (the row): it opens just below that box,
     * or above it when the view has no room below.
     */
    function openPopover(anchor: Item, calendarId: string, above: bool, edgeItem: Item) {
        if (colorPopover.shown && root.popoverCalendarId === calendarId) {
            colorPopover.shown = false;
            return;
        }
        var p = root.mapFromItem(anchor, 0, 0);
        var e = root.mapFromItem(edgeItem, 0, 0);
        var wantedY = above ? e.y - colorPopover.height - 6 : e.y + edgeItem.height;
        if (!above && wantedY + colorPopover.height > root.height - 4) wantedY = e.y - colorPopover.height;
        root.popoverCalendarId = calendarId;
        root.popoverX = Math.max(4, Math.min(p.x - 4, root.width - colorPopover.width - 4));
        root.popoverY = Math.max(4, wantedY);
        colorPopover.shown = true;
    }

    function popoverPicked(key: string) {
        if (root.popoverCalendarId === "") root.newColor = key;
        else Calendar.setCalendarColor(root.popoverCalendarId, key);
    }

    // ---- link box state

    readonly property string link: linkInput.text.trim()
    readonly property bool linkValid: /^(?:https|webcal):\/\/[^\s/]+\.[^\s/]+\S*$/i.test(root.link)

    // Name of the calendar that already holds this link, or "".
    readonly property string subscribedName: {
        var feed = Queries.feedUrl(root.link);
        if (!root.linkValid || !feed) return "";
        var id = "l-" + Items.shortHash(feed);
        var list = Calendar.calendars || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) return list[i].name;
        }
        return "";
    }

    // Result of the last link check.
    property string checkedLink: ""
    property bool checkOk: false
    property int checkCount: 0
    property int checkDuplicates: 0
    property string checkError: ""

    /** Text after an action (import, subscribe). Cleared when the link text changes. */
    property string message: ""
    property bool messageIsError: false
    property int activeSubscription: 0
    readonly property bool subscribing: root.activeSubscription !== 0
    // Set for a few seconds after IMPORT FILE found events that other calendars already hold.
    property string importNote: ""

    readonly property bool checked: root.checkedLink === root.link
    readonly property bool canSubscribe: root.linkValid && root.subscribedName === "" && root.checked && root.checkOk && !root.subscribing

    // tone: mute | dim | error | accent
    readonly property var hint: {
        if (Calendar.parserError !== "") return { text: Calendar.parserError, tone: "error" };
        if (root.message !== "") return { text: root.message, tone: root.messageIsError ? "error" : "dim" };
        if (root.importNote !== "") return { text: root.importNote, tone: "dim" };
        if (root.link === "") return { text: "paste an .ics or webcal:// link", tone: "mute" };
        if (!root.linkValid) return { text: "not a feed link · use https:// or webcal://", tone: "error" };
        if (root.subscribedName !== "") return { text: "already subscribed · " + root.subscribedName, tone: "dim" };
        if (root.subscribing) return { text: "subscribing...", tone: "dim" };
        if (!root.checked) return { text: "checking the link...", tone: "dim" };
        if (!root.checkOk) return { text: root.checkError !== "" ? root.checkError : "could not read the link", tone: "error" };
        return {
            text: "↲ subscribe · valid feed · " + root.checkCount + (root.checkCount === 1 ? " event" : " events")
                + (root.checkDuplicates > 0 ? " · " + root.checkDuplicates + " already in your calendars" : " · refresh every 30 min"),
            tone: "accent"
        };
    }

    function toneColor(tone: string): color {
        switch (tone) {
        case "error": return root.redColor;
        case "accent": return Theme.accentLight;
        case "dim": return Theme.dim;
        default: return Theme.mute;
        }
    }

    /** Gives up keyboard focus (panel closed, click elsewhere). */
    function releaseFocus() {
        linkInput.releaseFocus();
        colorPopover.shown = false;
    }

    /** True when a scene point lies on the link box (so a click there keeps focus). */
    function linkContains(scenePoint): bool {
        return linkInput.containsLink(scenePoint);
    }

    /** Clears the link box and any message (the view is flipped). */
    function reset() {
        linkInput.text = "";
        root.message = "";
        root.importNote = "";
        root.checkedLink = "";
        root.activeSubscription = 0;
        checkTimer.stop();
        colorPopover.shown = false;
        root.newColor = Calendar.nextCalendarColor();
    }

    // The link text changed by typing or pasting: forget old results and check the new link after a pause.
    // textEdited comes before `link` and `linkValid` update, so the timer decides, not this function.
    function linkEdited() {
        root.message = "";
        root.importNote = "";
        checkTimer.restart();
    }

    function subscribe() {
        if (!root.canSubscribe) return;
        root.activeSubscription = Calendar.subscribe(root.link, root.newColor);
    }

    /** The host got a file from the dialog. */
    function importPicked(path: string) {
        var before = (Calendar.calendars || []).map(function (c) { return c.id; });
        var id = Calendar.importFile(path, root.newColor);
        if (id === "") {
            root.message = Calendar.lastError !== "" ? Calendar.lastError : "could not import the file";
            root.messageIsError = true;
            return;
        }
        var list = Calendar.calendars || [];
        var found = list.filter(function (c) { return c.id === id; })[0];
        var name = found ? found.name : "";
        root.message = (before.indexOf(id) >= 0 ? "already imported · " : "imported · ") + name
            + (found ? " · " + found.itemCount + (found.itemCount === 1 ? " item" : " items") : "");
        root.messageIsError = false;
        if (Calendar.lastImportDuplicates > 0) {
            root.message = "";
            root.importNote = "imported · " + Calendar.lastImportDuplicates + " already in your calendars";
            importNoteTimer.restart();
        }
        if (before.indexOf(id) < 0) root.newColor = Calendar.nextCalendarColor();
    }

    Timer {
        id: importNoteTimer
        interval: 4000
        onTriggered: root.importNote = ""
    }

    Timer {
        id: checkTimer
        interval: 500
        onTriggered: if (root.linkValid && root.subscribedName === "") Calendar.checkLink(root.link)
    }

    Connections {
        target: Calendar

        function onLinkChecked(url, ok, name, eventCount, error, duplicateCount) {
            if (url !== root.link) return;
            root.checkedLink = url;
            root.checkOk = ok;
            root.checkCount = eventCount;
            root.checkDuplicates = duplicateCount || 0;
            root.checkError = error;
        }

        function onSubscribed(url, id, error, requestId) {
            if (!root.subscribing || requestId !== root.activeSubscription) return;
            root.activeSubscription = 0;
            if (error !== "") {
                root.message = error;
                root.messageIsError = true;
                return;
            }
            var found = (Calendar.calendars || []).filter(function (c) { return c.id === id; })[0];
            linkInput.text = "";
            root.checkedLink = "";
            root.message = "subscribed" + (found ? " · " + found.name + " · " + found.itemCount + (found.itemCount === 1 ? " item" : " items") : "");
            root.messageIsError = false;
            root.newColor = Calendar.nextCalendarColor();
        }

        function onCalendarsChanged() {
            root.refreshRows();
        }

        function onRevisionChanged() {
            root.refreshRows();
        }
    }

    // ---- rows

    // "12m ago", "2d ago"; "just now" under a minute.
    property real now: Date.now()

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.now = Date.now()
    }

    onVisibleChanged: if (visible) root.now = Date.now()

    ListModel {
        id: rows
    }

    function rowOf(c) {
        return {
            calId: c.id,
            name: c.name,
            kind: c.kind,
            calColor: c.color,
            hidden: !!c.hidden,
            itemCount: c.itemCount || 0,
            source: c.source || "",
            updatedAt: c.updatedAt || 0,
            failure: c.error || ""
        };
    }

    // Matches the displayed rows with Calendar.calendars (sorted for display: berri first,
    // then others A to Z by name, case-insensitive and accent-aware). Removes gone rows,
    // updates kept ones, inserts new ones in sorted order.
    function refreshRows() {
        var wanted = (Calendar.calendars || []).map(root.rowOf);
        // Sort: "berri" first, then all others A to Z by name (case-insensitive, accent-aware).
        wanted.sort(function (a, b) {
            if (a.calId === "berri") return -1;
            if (b.calId === "berri") return 1;
            return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
        });
        ShownRows.matchRows(rows, wanted, "calId");
    }

    Component.onCompleted: root.refreshRows()

    // ---- look

    Rectangle {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 22
        color: Theme.sunk

        Repeater {
            model: [
                { label: "NAME", x: 12 },
                { label: "UPDATED", x: root.updatedX }
            ]

            delegate: MonoText {
                required property var modelData

                x: modelData.x
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 1
                text: modelData.label
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 1.26
                color: Theme.dim
            }
        }
    }

    Rectangle {
        id: listCard
        anchors.top: headerRow.bottom
        anchors.topMargin: 1
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        color: Theme.card

        AnimatedList {
            id: list
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: linkInput.top
            clip: true
            model: rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: CalendarSourceRow {
                id: sourceRow
                nameWidth: root.nameWidth
                updatedX: root.updatedX
                now: root.now
                redColor: root.redColor
                onColorRequested: square => root.openPopover(square, sourceRow.calId, false, sourceRow)
            }
        }

        CalendarLinkBox {
            id: linkInput
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            newColor: root.newColor
            canSubscribe: root.canSubscribe
            hintText: root.hint.text
            hintColor: root.toneColor(root.hint.tone)
            onTextEdited: root.linkEdited()
            onSubscribeRequested: root.subscribe()
            onResetRequested: root.reset()
            onImportRequested: root.importRequested()
            onColorRequested: square => root.openPopover(square, "", true, square)
        }
    }

    // A click outside the popover closes it.
    MouseArea {
        anchors.fill: parent
        z: 9
        enabled: colorPopover.shown
        onPressed: colorPopover.shown = false
    }

    CalendarColorPopover {
        id: colorPopover
        z: 10
        x: root.popoverX
        y: root.popoverY
        colorKey: root.popoverCalendarId === "" ? root.newColor : root.colorOfCalendar(root.popoverCalendarId)
        onPicked: key => root.popoverPicked(key)
        onCloseRequested: colorPopover.shown = false
    }
}
