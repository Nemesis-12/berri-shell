import QtQuick
import "../../logic/CalendarDraft.js" as CalendarDraft
import qs.common
import qs.services

// Date, time, color and repeat rows. Edits go to the draft owner.
Column {
    id: root

    required property var draft
    required property var types
    required property var repeats
    property bool readOnly: false
    property real lockedOpacity: 1
    property real timeShown: 1
    property real endShown: 1
    property real resetShown: 0
    readonly property bool textEntryActive: dateField.textEntryActive || timeField.textEntryActive
        || endField.textEntryActive || hexField.input.activeFocus

    signal edited(string field, var changes)
    signal typePicked(string key)
    signal repeatPicked(string key)
    signal escaped
    signal resetColor

    // Gives up every field cursor when the form or panel closes.
    function releaseFocus() {
        dateField.releaseFocus();
        timeField.releaseFocus();
        endField.releaseFocus();
        hexField.input.focus = false;
    }

    // Kind.
    SegmentRow {
        width: parent.width
        enabled: !root.readOnly
        opacity: root.lockedOpacity
        cellHeight: 28
        spacingText: 0.72
        options: root.types
        current: root.draft.type
        onPicked: key => root.typePicked(key)
    }

    // Date, full width.
    Item {
        width: parent.width
        height: 10 + 44
        enabled: !root.readOnly
        opacity: root.lockedOpacity

        FormField {
            id: dateField
            y: 10
            width: parent.width
            label: "DATE"
            value: root.draft.date
            validate: CalendarDraft.validDate
            onEscaped: root.escaped()
            onTyped: v => root.edited("date", { date: v })
            onStepped: dir => root.edited("date", { date: CalendarDraft.stepDate(root.draft.date, dir) })
        }
    }

    // Start and end side by side. Tasks and reminders have only the start; all-day items have no time.
    Item {
        width: parent.width
        height: (10 + 44) * root.timeShown
        clip: true
        enabled: !root.readOnly
        opacity: root.timeShown * root.lockedOpacity

        FormField {
            id: timeField
            y: 10
            width: parent.width - root.endShown * ((parent.width - 6) / 2 + 6)
            label: root.draft.type === "reminder" ? "ALERT AT" : root.draft.type === "task" ? "DUE (OPTIONAL)" : "START"
            value: root.draft.time
            allowEmpty: root.draft.type === "task"
            validate: CalendarDraft.validTime
            onEscaped: root.escaped()
            onTyped: v => root.edited("time", { time: v })
            onStepped: dir => root.edited("time", { time: CalendarDraft.stepTime(root.draft.time, dir) })
        }

        FormField {
            id: endField
            y: 10
            x: timeField.width + 6
            width: (parent.width - 6) / 2
            visible: root.endShown > 0
            opacity: root.endShown
            label: "END"
            value: root.draft.end
            allowEmpty: true
            validate: CalendarDraft.validTime
            onEscaped: root.escaped()
            onTyped: v => root.edited("end", { end: v })
            onStepped: dir => root.edited("end", { end: CalendarDraft.stepTime(root.draft.end, dir) })
        }
    }

    // Color: 8 sharp 12px squares, 6px apart, then the hex box on the same row.
    // Stays live for a read-only item. RESET sits at the row's end while the item has an own color.
    Item {
        width: parent.width
        height: 10 + 28

        Row {
            id: swatches
            y: 10 + 8
            spacing: 6

            Repeater {
                model: CalendarColors.presets

                delegate: CalendarSwatch {
                    required property var modelData

                    colorKey: modelData.key
                    selected: root.draft.color === modelData.key
                    ringGap: Theme.card
                    onClicked: root.edited("color", { color: modelData.key })
                }
            }
        }

        CalendarHexField {
            id: hexField
            x: swatches.width + 12
            y: 10
            width: parent.width - x - resetButton.width * root.resetShown
            colorKey: root.draft.color
            onPicked: hex => root.edited("color", { color: hex })
        }

        // Removes the own color of a read-only item (back to the calendar's color) and closes.
        HoverButton {
            id: resetButton
            anchors.right: parent.right
            y: 10
            sidePadding: 8
            height: 28
            visible: root.resetShown > 0
            opacity: root.resetShown
            label: "RESET"
            hoverFill: "transparent"
            textColor: Theme.dim
            onClicked: root.resetColor()
        }
    }

    // Repeat.
    Item {
        width: parent.width
        height: 10 + 28
        enabled: !root.readOnly
        opacity: root.lockedOpacity

        SegmentRow {
            y: 10
            width: parent.width
            cellHeight: 26
            spacingText: 0.72
            options: root.repeats
            current: root.draft.repeat
            onPicked: key => root.repeatPicked(key)
        }
    }
}
