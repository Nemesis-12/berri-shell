import QtQuick
import qs.services
import qs.common

/**
 * The tray row at the right end of the hovered pill: up to 3 app buttons,
 * then a "+N" chip for the rest. Pure view; Pill decides what opens.
 */
Row {
    id: root

    /** All visible tray items, already sorted. */
    property var items: []

    /** The item whose menu is open, or null. */
    property var menuItem: null

    /** True while the "+N" popover is open. */
    property bool gridOpen: false

    /** The item flashed after a left click. */
    property var flashItem: null

    signal activated(var item, Item button)
    signal menuRequested(var item, Item button)
    signal moreClicked(Item chip)

    readonly property var shown: items.slice(0, PillTrayStyle.shownCount)
    readonly property int moreCount: Math.max(0, items.length - PillTrayStyle.shownCount)

    spacing: PillTrayStyle.gap
    height: PillTrayStyle.buttonSize

    Repeater {
        model: root.shown

        delegate: PillTrayButton {
            required property var modelData
            trayItem: modelData
            menuOpen: root.menuItem === modelData
            flash: root.flashItem === modelData
            onActivated: root.activated(modelData, this)
            onMenuRequested: root.menuRequested(modelData, this)
        }
    }

    // "+N" chip.
    Item {
        id: chip
        visible: root.moreCount > 0
        width: visible ? Math.max(PillTrayStyle.chipMinWidth, label.implicitWidth + 6) : 0
        height: PillTrayStyle.buttonSize

        readonly property bool lit: chipHover.hovered || root.gridOpen

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: chip.lit ? PillTrayStyle.hoverFill : PillTrayStyle.hoverFillClear
            ColorFade on color {}
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: "+" + root.moreCount
            font.family: Theme.mono
            font.weight: Font.DemiBold
            font.pixelSize: 10
            color: chip.lit ? Theme.fg : Theme.dim
            ColorFade on color {}
        }

        HoverHandler { id: chipHover }

        MouseArea {
            anchors.fill: parent
            onClicked: root.moreClicked(chip)
        }
    }
}
