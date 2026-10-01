import QtQuick
import qs.common
import qs.services

// Keeps the form actions at the bottom while color actions reveal.
Row {
    id: root

    property bool isEdit: false
    property bool readOnly: false
    property string repeat: "none"
    property string calendarName: ""
    property bool canSave: false
    property bool colorDiffers: false
    property real allShown: 0
    property real saveShown: 1
    property real saveDim: 1
    signal removed
    signal closed
    signal calendarColored
    signal accepted

    height: 36
    spacing: 1

    HoverButton {
        id: deleteButton
        visible: root.isEdit && !root.readOnly
        height: 36
        sidePadding: 12
        label: root.repeat !== "none" ? "DELETE SERIES" : "DELETE"
        fill: Theme.raised
        hoverFill: Theme.hover
        textColor: Theme.fg2
        hoverTextColor: Theme.fg
        onClicked: root.removed()
    }

    Item {
        width: parent.width - (deleteButton.visible ? deleteButton.width + 1 : 0) - cancelButton.width - (allSlot.visible ? allSlot.width + 1 : 0) - (saveSlot.visible ? saveSlot.width + 1 : 0) - 1
        height: 1
    }

    HoverButton {
        id: cancelButton
        height: 36
        sidePadding: 12
        label: root.readOnly ? "CLOSE" : "CANCEL"
        fill: "transparent"
        hoverFill: "transparent"
        textColor: Theme.dim
        hoverTextColor: Theme.fg
        onClicked: root.closed()
    }

    // ALL IN <calendar>: same slide as SAVE, one value for both. The name is cut to fit the row.
    Item {
        id: allSlot
        visible: root.allShown > 0
        width: allButton.width * root.allShown
        height: 36
        clip: true

        HoverButton {
            id: allButton
            height: 36
            sidePadding: 12
            x: allButton.width * (root.allShown - 1) * 0.5
            label: "ALL IN " + root.calendarName.toUpperCase()
            // Room left when the row shows delete, close and save too, minus a gap of 8 and the button's padding.
            maxTextWidth: Math.max(40, root.width - (deleteButton.visible ? deleteButton.width + 1 : 0) - cancelButton.width - 1
                - saveButton.width - 1 - 1 - 8 - 2 * sidePadding)
            fill: Theme.raised
            hoverFill: Theme.hover
            textColor: Theme.fg2
            hoverTextColor: Theme.fg
            opacity: root.allShown
            onClicked: root.calendarColored()
        }
    }

    // SAVE. In the read-only form it slides in (and takes room from the gap) only while the color changed.
    Item {
        id: saveSlot
        visible: root.saveShown > 0
        width: saveButton.width * root.saveShown
        height: 36
        clip: true

        HoverButton {
            id: saveButton
            height: 36
            x: saveButton.width * (root.saveShown - 1) * 0.5
            label: "SAVE"
            sidePadding: 18
            weight: Font.DemiBold
            letterSpacing: 1.26
            fill: Theme.accent
            hoverFill: root.canSave || root.colorDiffers ? Theme.accentLight : Theme.accent
            textColor: Theme.onAccent
            hoverTextColor: Theme.onAccent
            opacity: root.saveShown * root.saveDim
            onClicked: root.accepted()
        }
    }
}
