import QtQuick
import "../../logic/CalendarDraft.js" as CalendarDraft
import "../../logic/Times.js" as Times
import qs.common
import qs.pill
import qs.services

// Edits one calendar item. Owns the draft, save actions and reversible motion.
// Typed title parts fill untouched fields through CalendarDraft.
// A subscribed item permits color changes only. Repeat edits apply to the series.
Item {
    id: root

    /** True while the form is open (or opening). */
    property bool shown: false

    /** Set by the tab: true while the panel is open. The form gives up focus when it closes. */
    property bool panelOpen: true

    /** 24-hour times in the hint line. */
    property bool clock24: false

    /** True while a text field of the form has keyboard focus. The panel window asks for keyboard input then. */
    readonly property bool textEntryActive: titleField.textEntryActive || fields.textEntryActive

    /** Sent after SAVE, with the item's day ("YYYY-MM-DD"), so the month grid can show it. */
    signal saved(string dateKey)

    // Draft. type: event | allday | task | reminder.
    property string uid: ""
    property string type: "event"
    // Text in the title field, and the title left when the words that filled fields are cut out.
    property string raw: ""
    property string title: ""
    property string date: ""
    property string time: ""
    property string end: ""
    // Preset key ("accent", "blue", ...) or "#rrggbb".
    property string color: "accent"
    property string repeat: "none"
    property var byDay: []
    // Values the form opened with, and the fields the user set by hand ({ type: true, ... }).
    property var base: ({ type: "event", date: "", time: "", end: "", color: "accent", repeat: "none", byDay: [] })
    property var touched: ({})
    // One title reading supplies both the draft fields and the hint.
    property var titleParts: null
    readonly property var draft: ({
        raw: root.raw, title: root.title, type: root.type, date: root.date,
        time: root.time, end: root.end, color: root.color,
        repeat: root.repeat, byDay: root.byDay
    })
    // The stored item while editing: its day and end day move together.
    property var original: null
    // An item of a subscribed link: shown, not editable.
    property bool readOnly: false
    property string calendarName: ""
    // Names of the other calendars that hold the same event ("" when it is not shared).
    property string alsoInNames: ""
    // Calendar of the opened item: its id and kind ("local", "file" or "link"). Empty for a new item.
    property string calendarId: ""
    property string calendarKind: ""
    // Read-only item: the user gave it a color of their own.
    property bool hasOwnColor: false

    // Read-only item: the chosen color differs from the color the form opened with.
    readonly property bool colorDiffers: root.readOnly && root.color !== root.base.color

    // The item's calendar comes from a file or a link and the chosen color differs: ALL IN offers that color to the whole calendar.
    readonly property bool canColorCalendar: root.uid !== "" && (root.calendarKind === "file" || root.calendarKind === "link") && root.color !== root.base.color

    readonly property bool isEdit: root.uid !== ""
    readonly property bool canSave: !root.readOnly && root.title.trim() !== ""

    readonly property var types: [
        { key: "event", label: "Event" }, { key: "allday", label: "All-day" },
        { key: "task", label: "Task" }, { key: "reminder", label: "Reminder" }
    ]
    readonly property var repeats: [
        { key: "none", label: "Once" }, { key: "daily", label: "Daily" },
        { key: "weekly", label: "Weekly" }, { key: "monthly", label: "Monthly" }
    ]

    /** 0 = hidden, 1 = fully shown, in a straight line. Only `shown` sets it. */
    property real phase: root.shown ? 1 : 0

    Behavior on phase {
        NumberAnimation { duration: 240; easing.type: Easing.Linear }
    }

    // Phase with the mock's ease-out curve, cubic-bezier(.4, 0, .2, 1).
    readonly property real progress: Theme.easeOut(root.phase)

    visible: root.progress > 0

    // ---- opening and closing

    function typeLabel(key: string): string {
        return CalendarDraft.typeLabel(key, root.types);
    }

    function begin() {
        root.shown = true;
        titleField.begin(root.readOnly || root.uid !== "");
    }

    // Starts a draft from the given fields. Nothing is touched yet.
    function openDraft(fields: var, text: string) {
        root.base = fields;
        root.touched = ({});
        root.type = fields.type;
        root.date = fields.date;
        root.time = fields.time;
        root.end = fields.end;
        root.color = fields.color;
        root.repeat = fields.repeat;
        root.byDay = fields.byDay;
        root.raw = text;
        root.title = text;
        root.titleParts = root.readOnly ? null : CalendarDraft.parseLine(text, fields, new Date(), root.clock24);
        titleField.setText(text);
        root.begin();
    }

    /** NEW and a double-click on a day: an empty event on the given day, on the last used color. */
    function openNew(day: date) {
        root.uid = "";
        root.original = null;
        root.readOnly = false;
        root.calendarName = "";
        root.alsoInNames = "";
        root.calendarId = "";
        root.calendarKind = "";
        root.hasOwnColor = false;
        root.openDraft({
            type: "event", date: Times.dayKey(day), time: "09:00", end: "10:00",
            color: CalendarColors.lastColor, repeat: "none", byDay: []
        }, "");
    }

    /** A click on an item: edit the stored item (view it, when it comes from a subscribed link). */
    function openEdit(itemUid: string, occurrenceDate: string) {
        var item = Calendar.getItem(itemUid);
        if (!item) return;
        var shown = (Calendar.itemsOn(occurrenceDate || item.date) || []).filter(function (o) { return o.uid === itemUid; })[0];
        var readOnly = shown ? !!shown.readOnly : !!item.readOnly;
        var calendarId = shown ? shown.calendarId : item.calendarId;
        var calendar = (Calendar.calendars || []).filter(function (c) { return c.id === calendarId; })[0];
        root.original = item;
        root.uid = item.uid;
        root.readOnly = readOnly;
        root.calendarName = calendar ? calendar.name : "";
        root.alsoInNames = shown && shown.alsoIn ? shown.alsoIn.join(" + ") : "";
        root.calendarId = calendarId || "";
        root.calendarKind = calendar ? calendar.kind : "";
        root.hasOwnColor = readOnly && !!(shown ? shown.hasOwnColor : item.hasOwnColor);
        root.openDraft({
            type: item.kind === "event" && item.time === null ? "allday" : item.kind,
            date: item.date,
            time: item.time || "",
            end: item.end || "",
            color: (shown && shown.color) || item.color || CalendarColors.lastColor,
            repeat: item.repeat || "none",
            byDay: item.byDay || []
        }, item.title);
    }

    function close() {
        releaseFocus();
        root.shown = false;
    }

    /** Gives up keyboard focus (panel closed, form closed). */
    function releaseFocus() {
        titleField.releaseFocus();
        fields.releaseFocus();
    }

    onPanelOpenChanged: if (!root.panelOpen) root.releaseFocus()

    // ---- natural text in the title

    // The title text was edited by the user: fill the fields that are not touched.
    function titleEdited(text: string) {
        var titleDraft = CalendarDraft.fromText(root.base, root.touched, root.draft, text, new Date(), root.clock24);
        for (var field in titleDraft.fields) root[field] = titleDraft.fields[field];
        root.titleParts = titleDraft.line;
    }

    readonly property var hint: CalendarDraft.buildHint(root.titleParts, root.touched, root.draft, root.clock24, root.readOnly)

    // Last hint text and color, kept while the hint line fades out.
    property string hintText: ""
    property string hintSwatch: ""
    onHintChanged: if (root.hint) {
        root.hintText = root.hint.text;
        root.hintSwatch = root.hint.swatch;
    }

    // ---- draft changes by hand (the field is touched from now on)

    function setByHand(key: string, changes: var) {
        var touched = Object.assign({}, root.touched);
        touched[key] = true;
        root.touched = touched;
        for (var name in changes) root[name] = changes[name];
    }

    function setType(key: string) {
        root.setByHand("type", { type: key, time: key === "allday" ? "" : (root.time || (key === "task" ? "" : "09:00")) });
    }

    function setRepeat(key: string) {
        root.setByHand("repeat", {
            repeat: key,
            byDay: key === "weekly" && root.original && root.original.repeat === "weekly" ? root.original.byDay : []
        });
    }

    // ---- save and delete

    // A read-only item can only get its own color. "" removes it.
    function saveColorOnly(color: string) {
        Calendar.setItemColor(root.uid, color);
        root.close();
    }

    // ALL IN: the chosen color goes to the whole calendar and clears the colors of its items.
    function colorWholeCalendar() {
        if (!root.canColorCalendar) return;
        Calendar.applyColorToCalendar(root.calendarId, root.color);
        root.close();
    }

    function save() {
        if (root.readOnly) {
            if (root.colorDiffers) root.saveColorOnly(root.color);
            return;
        }
        if (!root.canSave) return;
        var fields = CalendarDraft.toStoredFields(root.draft, root.original);
        if (root.isEdit) Calendar.update(root.uid, fields);
        else Calendar.add(fields);
        CalendarColors.lastColor = root.color;
        root.saved(root.date);
        root.close();
    }

    function remove() {
        if (root.isEdit && !root.readOnly) Calendar.remove(root.uid);
        root.close();
    }

    // One reversible reveal per row or action. Each part draws from value.
    Reveal { id: hintReveal; on: !!root.hint }
    Reveal { id: timeReveal; on: root.type !== "allday" }
    Reveal { id: endReveal; on: root.type === "event" }
    Reveal { id: swatchReveal; on: !!root.hint && root.hint.swatch !== "" }
    Reveal { id: lockReveal; on: root.readOnly }
    Reveal { id: resetReveal; on: root.hasOwnColor }
    Reveal { id: saveReveal; on: !root.readOnly || root.colorDiffers }
    Reveal { id: allReveal; on: root.canColorCalendar }

    // An empty editable title dims SAVE without changing its reveal motion.
    property real saveDim: root.readOnly || root.canSave ? 1 : 0.45
    Fade on saveDim {}

    // Blocks clicks on the list under the form.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
    }

    // Card: fades in during the first half of the motion; the content in the second half.
    Rectangle {
        anchors.fill: parent
        color: Theme.card
        opacity: Math.min(1, root.progress * 2)
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: Math.max(0, root.progress * 2 - 1)
        transform: Translate { y: 8 * (1 - root.progress) }

        // Heading reads bottom to top.
        Item {
            id: headingBox
            x: 10
            y: 12
            width: 9
            height: parent.height - 26

            MonoText {
                // Rotated text is centered in the 9px line box, like the mock's vertical text.
                x: Math.round((headingBox.width - implicitHeight) / 2 * 2) / 2
                y: headingBox.height
                rotation: -90
                transformOrigin: Item.TopLeft
                text: (root.readOnly ? "VIEW " : root.isEdit ? "EDIT " : "NEW ") + root.typeLabel(root.type).toUpperCase()
                font.family: Theme.mono
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 1.62
                color: Theme.dim
            }
        }

        // Everything above the buttons. It scrolls when the title is long and the panel is short.
        Flickable {
            id: body
            x: 29
            y: 12
            width: parent.width - 29 - 14
            height: parent.height - 12 - 14 - 36 - 8
            contentWidth: width
            contentHeight: flow.height
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Item {
                id: flow
                width: body.width
                height: fields.y + fields.height

                TitleField {
                    id: titleField
                    anchors.top: parent.top
                    width: parent.width
                    availableHeight: body.height - (flow.height - height)
                    readOnly: root.readOnly
                    onEdited: text => root.titleEdited(text)
                    onAccepted: root.save()
                    onEscaped: root.close()
                    onClosed: root.close()
                }

                // The hint keeps its last text while it fades out.
                Item {
                    id: hintBlock
                    anchors.top: titleField.bottom
                    width: parent.width
                    height: 14 * hintReveal.value

                    Item {
                        y: 4
                        x: 2
                        width: parent.width - 2
                        height: 10
                        opacity: hintReveal.value

                        Icon {
                            size: 10
                            name: "corner-down-left"
                            strokeWidth: 2.4
                            color: Theme.accentLight
                        }

                        MonoText {
                            id: hintLabel
                            x: 15
                            width: Math.min(implicitWidth, parent.width - 15 - 14 * swatchReveal.value)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: root.hintText
                            font.letterSpacing: 0.54
                            color: Theme.accentLight
                        }

                        Rectangle {
                            x: hintLabel.x + hintLabel.width + 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            opacity: swatchReveal.value
                            color: root.hintSwatch !== "" ? CalendarColors.resolve(root.hintSwatch) : "transparent"
                        }
                    }
                }

                CalendarFormFields {
                    id: fields
                    anchors.top: hintBlock.bottom
                    anchors.topMargin: 10
                    width: parent.width
                    draft: root.draft
                    types: root.types
                    repeats: root.repeats
                    readOnly: root.readOnly
                    lockedOpacity: 1 - 0.45 * lockReveal.value
                    timeShown: timeReveal.value
                    endShown: endReveal.value
                    resetShown: resetReveal.value
                    onEdited: (field, changes) => root.setByHand(field, changes)
                    onTypePicked: key => root.setType(key)
                    onRepeatPicked: key => root.setRepeat(key)
                    onEscaped: root.close()
                    onResetColor: root.saveColorOnly("")
                }
            }
        }

        CalendarFormButtons {
            x: 29
            width: parent.width - 29 - 14
            y: parent.height - 14 - height
            isEdit: root.isEdit
            readOnly: root.readOnly
            repeat: root.repeat
            calendarName: root.calendarName
            canSave: root.canSave
            colorDiffers: root.colorDiffers
            allShown: allReveal.value
            saveShown: saveReveal.value
            saveDim: root.saveDim
            onRemoved: root.remove()
            onClosed: root.close()
            onCalendarColored: root.colorWholeCalendar()
            onAccepted: root.save()
        }
    }
}
