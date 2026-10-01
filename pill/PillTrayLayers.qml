import QtQuick

/**
 * Everything the tray opens outside the pill: the "+N" popover grid, an
 * app's right-click menu, and a full-screen click catcher that closes them.
 * Fill the monitor with this item. The owner widens the input mask and
 * asks for keyboard focus while `open` holds.
 */
Item {
    id: root

    /** All visible tray items, sorted. */
    property var items: []

    /** Items that did not fit in the pill (shown in the grid). */
    readonly property var moreItems: items.slice(PillTrayStyle.shownCount)

    readonly property bool gridOpen: gridPopover.open
    readonly property bool menuOpen: menuPopover.open
    readonly property bool open: gridOpen || menuOpen

    /** The item whose menu is showing, or null. */
    property var menuItem: null

    /** The item flashed after a left click. */
    property var flashItem: null

    readonly property int margin: 8

    function closeAll() {
        gridPopover.open = false;
        menuPopover.open = false;
        root.menuItem = null;
    }

    /** Left click: open the app (or its menu when it has only a menu). */
    function activate(item, button) {
        if (item.onlyMenu && item.hasMenu) {
            openMenu(item, button);
            return;
        }
        closeAll();
        item.activate();
        root.flashItem = item;
        flashTimer.restart();
    }

    /** Right click: the app's menu, or its secondary action without one. */
    function openMenu(item, button) {
        if (!item.hasMenu) {
            closeAll();
            item.secondaryActivate();
            return;
        }
        const spot = button.mapToItem(root, button.width / 2, button.height);
        gridPopover.open = false;
        menuPopover.x = Math.max(margin, Math.min(root.width - menuPopover.width - margin, spot.x - 22));
        menuPopover.y = spot.y + 8;
        menuPopover.handle = item.menu;
        menuPopover.title = item.title !== "" ? item.title : item.id;
        root.menuItem = item;
        menuPopover.open = true;
        root.forceActiveFocus();
    }

    /** The "+N" chip: toggles the grid under it. */
    function toggleGrid(chip) {
        if (gridPopover.open) {
            closeAll();
            return;
        }
        const spot = chip.mapToItem(root, chip.width / 2, chip.height);
        menuPopover.open = false;
        root.menuItem = null;
        gridPopover.x = Math.max(margin, Math.min(root.width - gridPopover.width - margin, spot.x - gridPopover.width / 2));
        gridPopover.y = spot.y + 8;
        gridPopover.open = true;
        root.forceActiveFocus();
    }


    Keys.onEscapePressed: root.closeAll()

    Timer {
        id: flashTimer
        interval: 900
        onTriggered: root.flashItem = null
    }

    // Any click outside the popovers closes them.
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        acceptedButtons: Qt.AllButtons
        onClicked: root.closeAll()
    }

    PillTrayPopover {
        id: gridPopover

        readonly property int columns: root.moreItems.length <= 4 ? 2 : 3
        readonly property int rows: Math.ceil(root.moreItems.length / columns)
        readonly property int cellWidth: PillTrayStyle.buttonSize + 4

        width: 14 + columns * cellWidth + (columns - 1) * PillTrayStyle.gap
        height: 14 + rows * PillTrayStyle.buttonSize + Math.max(0, rows - 1) * PillTrayStyle.gap

        Grid {
            x: 7
            y: 7
            columns: gridPopover.columns
            columnSpacing: PillTrayStyle.gap
            rowSpacing: PillTrayStyle.gap

            Repeater {
                model: root.moreItems

                delegate: Item {
                    required property var modelData
                    width: gridPopover.cellWidth
                    height: PillTrayStyle.buttonSize

                    PillTrayButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        trayItem: modelData
                        menuOpen: root.menuItem === modelData
                        flash: root.flashItem === modelData
                        onActivated: root.activate(modelData, this)
                        onMenuRequested: root.openMenu(modelData, this)
                    }
                }
            }
        }
    }

    PillTrayMenu {
        id: menuPopover
        onFinished: root.closeAll()
    }
}
