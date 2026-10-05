import QtQuick
import qs.common
import qs.services
import qs.tabs.code
import qs.tabs.system
import qs.tabs.weather

/**
 * Home tab grid: fills the panel's content area with the empty cell
 * layout from the mock's 5C SPINE block (Berri Dashboard v2.dc.html,
 * ~line 328). Each cell is a plain Theme.card rectangle; the 1px gaps
 * between them show this item's own Theme.border backdrop (the tab area
 * behind it is Theme.card, so the lines need their own backdrop). The
 * backdrop fills the item exactly, so the outer edge gets no extra line.
 * Cell tickets fill in content by targeting these ids later.
 */
Item {
    id: root

    readonly property int gap: 1

    /** What this tab asks of the panel: keyboard focus for the Wi-Fi password row, and the panel closed before a chooser opens. */
    readonly property PanelRequests requests: PanelRequests {
        wantsKeyboard: root.wifiPasswordActive
    }

    // The panel sits on the Overlay layer above a normal dialog window, so a
    // chooser would open hidden underneath it. The chooser opens once the panel is closed.
    Connections {
        target: profileCell
        function onPictureClicked() {
            root.requests.dialogRequested(() => profileCell.openPictureChooser(), true);
        }
    }

    Connections {
        target: stickerCell
        function onStickerClicked() {
            root.requests.dialogRequested(() => stickerCell.openStickerChooser(), true);
        }
    }

    /** Top-level item tooltips reparent into so cell clipping never cuts them off. */
    property Item tooltipLayer: null

    /** Size this tab has once the panel is fully open (set by Pill). The Sticker decodes its image at its final cell size. */
    property size restSize: Qt.size(0, 0)

    /** True while the dashboard panel is open; passed to Sticker to pause its
     *  GIF while hidden, and to QuickToggles to reset its Wi-Fi list to the grid. */
    property bool panelOpen: false

    /** Bubbled up from QuickToggles: true while the Wi-Fi list's password row wants keyboard focus. */
    readonly property bool wifiPasswordActive: quickToggles.wifiPasswordActive

    // The usage rings (SystemRings) read these; they sample only while Home is on screen.
    WhileVisible { service: SystemUsage }
    WhileVisible { service: CpuLoad }

    // Line color: shows only through the 1px gaps between cells.
    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // Top part: left/middle/media columns, 363px tall.
    Item {
        id: topPart
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 363

        // Left column, 240 wide: dateClock, weather, profile, battery.
        Item {
            id: leftColumn
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 240

            Rectangle {
                id: dateClock
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 120
                color: Theme.card
                topLeftRadius: 7

                DateClock {
                    anchors.fill: parent
                }
            }

            Rectangle {
                id: weather
                anchors.top: dateClock.bottom
                anchors.topMargin: root.gap
                anchors.left: parent.left
                anchors.right: parent.right
                height: 64
                color: Theme.card

                CurrentWeather {
                    anchors.fill: parent
                }
            }

            Rectangle {
                id: profile
                anchors.top: weather.bottom
                anchors.topMargin: root.gap
                anchors.left: parent.left
                anchors.right: parent.right
                height: 80
                color: Theme.card

                Profile {
                    id: profileCell
                    anchors.fill: parent
                }
            }

            Rectangle {
                id: battery
                anchors.top: profile.bottom
                anchors.topMargin: root.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Theme.card

                Battery {
                    anchors.fill: parent
                    tooltipLayer: root.tooltipLayer
                }
            }
        }

        // Middle column, 262 wide: toggles, faders.
        Item {
            id: middleColumn
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: leftColumn.right
            anchors.leftMargin: root.gap
            width: 262

            Rectangle {
                id: toggles
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 185
                color: Theme.card

                QuickToggles {
                    id: quickToggles
                    anchors.fill: parent
                    panelOpen: root.panelOpen
                }
            }

            Rectangle {
                id: faders
                anchors.top: toggles.bottom
                anchors.topMargin: root.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Theme.card

                Faders {
                    anchors.fill: parent
                }
            }
        }

        // Media column: remaining width, one cell full height.
        Rectangle {
            id: media
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: middleColumn.right
            anchors.leftMargin: root.gap
            anchors.right: parent.right
            color: Theme.card

            Media {
                anchors.fill: parent
            }
        }
    }

    // Bottom row, 88 tall: agents, system, sticker.
    Item {
        id: bottomRow
        anchors.top: topPart.bottom
        anchors.topMargin: root.gap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 88

        Rectangle {
            id: agents
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 240
            color: Theme.card
            bottomLeftRadius: 7

            AgentsRings {
                anchors.fill: parent
            }
        }

        Rectangle {
            id: system
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: agents.right
            anchors.leftMargin: root.gap
            width: 262
            color: Theme.card

            SystemRings {
                anchors.fill: parent
                tooltipLayer: root.tooltipLayer
            }
        }

        Rectangle {
            id: sticker
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: system.right
            anchors.leftMargin: root.gap
            anchors.right: parent.right
            color: Theme.card

            Sticker {
                id: stickerCell
                anchors.fill: parent
                // Rest size of this cell: the tab's width minus the agents (240) and system (262) cells, and its height minus the top part (363); plus their gaps.
                restSize: Qt.size(root.restSize.width - 240 - 262 - 2 * root.gap,
                    root.restSize.height - topPart.height - root.gap)
                panelOpen: root.panelOpen
            }
        }
    }
}
