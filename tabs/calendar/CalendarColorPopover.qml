import QtQuick
import qs.services

/**
 * Small color picker that floats over the calendars view: the 8 preset
 * squares and a hex box, on one row. A preset click sends `picked` and closes;
 * a valid hex sends `picked` while typing. A click outside closes it (the
 * host puts `outside` behind it). Open and close use one straight-line phase
 * shown through the ease-out curve, so close is open played backwards.
 */
Item {
    id: root

    /** The color the picker shows as chosen (preset key or "#rrggbb"). */
    property string colorKey: "accent"

    /** Open or closed. The host sets it. */
    property bool shown: false

    /** True while the hex box has keyboard focus. */
    readonly property bool textEntryActive: hexField.input.activeFocus

    /** A color was chosen: a preset key or "#rrggbb". */
    signal picked(string key)

    /** The popover wants to close (preset chosen, Esc). */
    signal closeRequested

    property real phase: root.shown ? 1 : 0

    Behavior on phase {
        NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.Linear }
    }

    readonly property real progress: Theme.easeOut(root.phase)

    /** Gives up keyboard focus. */
    function releaseFocus() {
        hexField.input.focus = false;
    }

    onShownChanged: if (!root.shown) root.releaseFocus()

    width: 10 + swatches.width + 12 + 96 + 10
    height: 10 + 28 + 10
    visible: root.phase > 0
    opacity: root.progress
    transform: Translate { y: -6 * (1 - root.progress) }

    Rectangle {
        anchors.fill: parent
        color: Theme.raised
        border.width: 1
        border.color: Theme.border
    }

    Row {
        id: swatches
        x: 10
        y: 10 + 8
        spacing: 6

        Repeater {
            model: CalendarColors.presets

            delegate: CalendarSwatch {
                required property var modelData

                colorKey: modelData.key
                selected: root.colorKey === modelData.key
                ringGap: Theme.raised
                onClicked: {
                    root.picked(modelData.key);
                    root.closeRequested();
                }
            }
        }
    }

    CalendarHexField {
        id: hexField
        x: swatches.x + swatches.width + 12
        y: 10
        width: 96
        colorKey: root.colorKey
        onPicked: hex => root.picked(hex)
        onEscaped: root.closeRequested()
    }
}
