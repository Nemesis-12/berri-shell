import QtQuick
import QtQuick.Window
import Quickshell.Services.SystemTray
import "../logic/PanelTimeline.js" as PanelTimeline
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/Timeline.js" as Timeline
import qs.common
import qs.dashboard
import qs.services
import qs.tabs.alerts
import qs.tabs.calendar
import qs.tabs.code
import qs.tabs.home
import qs.tabs.media
import qs.tabs.system
import qs.tabs.weather

/**
 * The top pill: a clock, centered, with the date, weather and system tray
 * revealed on hover. A click grows it into the dashboard (tab pages and the
 * spine). Sizes, colors and motion match the "MINIMAL / PILL" screen of the
 * berri mocks (TK.C, spine style).
 *
 * The grow is one motion. `progress` goes straight from 0 to 1 over `totalMs`;
 * every part (width, height, shadow, clock, dashboard, icon flight) shows its
 * own slice of the timeline below. Close runs `progress` back to 0, so the
 * parts run in reversed order, also when the close starts mid-way. While
 * closing, each slice is eased the other way round (see Timeline.js): every
 * part leaves fast and settles slowly into rest, like it does when it opens.
 */
Item {
    id: root

    readonly property int collapsedWidth: 124
    readonly property int expandedWidth: 188
    readonly property int pillHeight: 30
    readonly property int panelWidth: 800
    readonly property int panelHeight: 454

    // Open and close timelines, in ms after the click (see PanelTimeline.js). The icon flight sets its own length.
    readonly property int widenMs: PanelTimeline.pill.widenMs
    readonly property int growMs: PanelTimeline.pill.growMs
    readonly property int shadowMs: PanelTimeline.pill.shadowMs
    readonly property int clockFadeMs: PanelTimeline.pill.clockFadeMs
    /** The whole open motion: it ends when the icon flight ends. */
    readonly property int totalMs: iconFlight.endMs

    readonly property var closeTimes: PanelTimeline.pillClose(totalMs, iconFlight.closeEndMs)
    /** The dashboard fades and slides out, the shadow and the height start to fall. */
    readonly property int growCloseAtMs: closeTimes.growCloseAtMs
    /** The pill narrows when the height has fallen 3/4. */
    readonly property int widenCloseAtMs: closeTimes.widenCloseAtMs
    /** The clock returns when the pill has narrowed 3/5. */
    readonly property int clockCloseAtMs: closeTimes.clockCloseAtMs
    /** The time at which every step of the close is at rest. */
    readonly property int closeEndMs: closeTimes.closeEndMs

    /** True while a fullscreen window owns this monitor and the pill is not revealed; hides the pill. */
    property bool suppressed: false
    onSuppressedChanged: if (suppressed) trayLayers.closeAll()

    /** Set by PillPopup while a notification card covers the pill; fades the clock group out. */
    property bool popupActive: false

    /** Set by shell.qml (modelData.name); keys this monitor's PanelCoordinator entry. */
    property string screenName: ""

    /** True while the active tab asks for real keyboard focus (set from the tab's PanelRequests). shell.qml's overlay window grabs keyboard focus only while a panel needs it. */
    property bool tabWantsKeyboard: false

    /** True from the click until the dashboard is closed again: where the motion is going. */
    readonly property bool open: slide.open

    /** The open motion, 0 (pill) to 1 (dashboard), in a straight line over `totalMs`. */
    readonly property real progress: slide.progress

    /** Time since the open started, in ms. Every slice of the motion reads this. */
    readonly property real elapsedMs: slide.elapsedMs

    /** True while the motion runs toward the pill: every slice then eases out into rest. */
    readonly property bool closing: slide.closing

    /** True while the dashboard is open, opening or closing. */
    readonly property bool panelOpen: slide.active

    /** True once the pill is wide and the dashboard is meant to be open: the tab pages may work. */
    readonly property bool panelReady: open && elapsedMs >= widenMs

    /** True while the pointer is on the pill or a tray popover or menu is open. */
    readonly property bool pointerInside: (hoverHandler.hovered || trayLayers.open) && !suppressed

    /** The pointer reveal of date, weather and tray. Stays true while a tray popover or menu is open, so the pill does not shrink under it. */
    readonly property bool hovered: pointerInside && !panelOpen

    /** True while a tray popover or menu is open; shell.qml widens the input mask and asks for keyboard focus. */
    readonly property bool trayLayerOpen: trayLayers.open

    /** Tray apps to show: active ones only (Passive apps are hidden), in stable id order. */
    readonly property var trayItems: SystemTray.items.values
        .filter(item => item.status !== Status.Passive)
        .sort((a, b) => a.id < b.id ? -1 : (a.id > b.id ? 1 : 0))

    /** Hovered width: 188 alone; with a tray it grows by the tray row on both sides (388 for 3 icons + chip). */
    readonly property int hoverWidth: {
        const count = trayItems.length;
        if (count === 0) return expandedWidth;
        const buttons = Math.min(count, PillTrayStyle.shownCount);
        const parts = buttons + (count > buttons ? 1 : 0);
        const rowWidth = buttons * PillTrayStyle.buttonSize + (count > buttons ? PillTrayStyle.chipMinWidth : 0)
            + (parts - 1) * PillTrayStyle.gap;
        return expandedWidth + 8 + 2 * (6 + rowWidth);
    }

    /** The tabs in spine order: id, Lucide icon, spine label and page body. The spine, the icon flight and the tab pages are built from this list. */
    readonly property var tabs: [
        { id: "home", icon: "house", label: "HOME", body: homeBody },
        { id: "media", icon: "disc-3", label: "MEDIA", body: mediaBody },
        { id: "system", icon: "cpu", label: "SYSTEM", body: systemBody },
        { id: "code", icon: "code", label: "CODE", body: codeBody },
        { id: "calendar", icon: "calendar", label: "CALENDAR", body: calendarBody },
        { id: "weather", icon: "cloud", label: "WEATHER", body: weatherBody },
        { id: "alerts", icon: "bell", label: "ALERTS", body: alertsBody }
    ]

    /** Tab names in spine order (from `tabs`); the spine and the tab pages share this order. */
    readonly property var tabIds: tabs.map(tab => tab.id)

    /** Index of the active tab. Stays set while closed, so the panel opens on the last tab used on this monitor. */
    property int activeTab: 0

    /** Output scale (2 on eDP-2, 1 on HDMI-A-1); used to snap the pill to whole device pixels. */
    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    implicitWidth: expandedWidth
    implicitHeight: pillHeight

    opacity: suppressed ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // Slides in from the top edge with the fade (same progress: opacity).
    transform: Translate { y: PixelGrid.snap(-(1 - root.opacity) * 8, root.dpr) }

    // The one slide operation (see PanelSlide.qml): open, close, close at once, and dialog requests.
    PanelSlide {
        id: slide
        screenName: root.screenName
        kind: "pill"
        totalMs: root.totalMs
        closeEndMs: root.closeEndMs
    }

    /** Starts the open motion; also while a close is running. */
    function openPanel() {
        slide.openSlide();
    }

    /** Starts the close motion: the open steps in reversed order, each one easing out into rest. No-op unless open. */
    function closePanel() {
        slide.closeSlide();
    }

    /** Stops the dashboard motion and closes at once when fullscreen starts. */
    function closeAtOnce() {
        slide.closeAtOnce();
    }

    onPanelOpenChanged: if (panelOpen) trayLayers.closeAll()

    // The shadow of the pill; the open motion deepens it.
    PanelShadow {
        target: pillRect
        hovered: root.pointerInside
        hoverMs: root.shadowMs
        openProgress: Timeline.fadeSlice(root.elapsedMs, root.widenMs, root.shadowMs, root.closing, root.growCloseAtMs)
        restOffset: 4
        restStrength: 0.28
        restBlur: 14
        hoverOffset: 10
        hoverStrength: 0.38
        hoverBlur: 26
        openOffset: 24
        openStrength: 0.45
        openBlur: 32
    }

    Rectangle {
        id: pillRect

        // Half the rest width follows the pointer; the open motion widens it to
        // the panel. Width and x come from the rounded half-width, so both edges
        // land on a whole device pixel (no jitter at scale 2).
        property real restHalfWidth: (root.pointerInside ? root.hoverWidth : root.collapsedWidth) / 2
        Behavior on restHalfWidth {
            SpringMotion {
                duration: root.widenMs
            }
        }
        readonly property real halfWidth: restHalfWidth
            + (root.panelWidth / 2 - restHalfWidth) * Timeline.springSlice(root.elapsedMs, 0, root.widenMs, root.closing, root.widenCloseAtMs)

        y: 0
        width: PixelGrid.snap(halfWidth, root.dpr) * 2
        x: PixelGrid.snap(root.width / 2, root.dpr) - width / 2
        height: PixelGrid.snap(root.pillHeight
            + (root.panelHeight - root.pillHeight) * Timeline.springSlice(root.elapsedMs, root.widenMs, root.growMs, root.closing, root.growCloseAtMs), root.dpr)
        radius: 8
        color: Theme.shell
        border.width: 1
        border.color: root.panelOpen ? Theme.border : "transparent"
        clip: true

        HoverHandler {
            id: hoverHandler
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.openPanel()
        }

        // Clock/date/weather; hidden while opening/open/closing, shown at rest.
        PillClockGroup {
            id: clockGroup
            anchors.fill: parent
            hovered: root.hovered
            popupActive: root.popupActive
            pillShown: root.opacity > 0.001
            dpr: root.dpr
            elapsedMs: root.elapsedMs
            closing: root.closing
            clockFadeMs: root.clockFadeMs
            clockCloseAtMs: root.clockCloseAtMs
            trayItems: root.trayItems
            trayLayers: trayLayers
        }

        // Dashboard frame: content area (left) + spine column (right). Fades in
        // and slides down a little while the pill grows, each on its own slice.
        Item {
            id: dashboard
            // Inset 1px so pillRect's own outline (border.width 1, radius 8)
            // stays visible around the frame instead of being painted over.
            anchors.fill: parent
            anchors.margins: 1
            opacity: Timeline.fadeSlice(root.elapsedMs, root.widenMs + 300, 260, root.closing, root.totalMs)
            visible: opacity > 0.001
            enabled: root.panelReady

            transform: Translate {
                id: dashboardSlide
                y: -8 * (1 - Timeline.springSlice(root.elapsedMs, root.widenMs + 220, 450, root.closing, root.totalMs))
            }

            // Shows through as the 1px gap between content area and spine.
            // Radius matches the outer 8px corner minus the 1px inset.
            Rectangle {
                anchors.fill: parent
                radius: 7
                color: Theme.border
            }

            Rectangle {
                id: contentArea
                x: 0
                y: 0
                width: parent.width - spine.width - 1
                height: parent.height
                color: Theme.card
                topLeftRadius: 7
                bottomLeftRadius: 7
                clip: true

                // Tab body host: one TabPage per tab, crossfaded by the active tab.
                // A tab body is built the first time its tab is shown, and then kept.
                Repeater {
                    model: root.tabs

                    delegate: TabPage {
                        id: page
                        required property var modelData

                        tabId: modelData.id
                        current: root.tabIds[root.activeTab]

                        /** True once this tab has been shown. Keeps the body loaded after the tab is hidden. */
                        property bool everOpened: false
                        onShownChanged: if (shown) page.everOpened = true
                        Component.onCompleted: if (shown) page.everOpened = true

                        Loader {
                            id: body
                            anchors.fill: parent
                            active: page.everOpened
                            sourceComponent: page.modelData.body

                            /** What the tab asks of the panel (its PanelRequests), or null for a tab that asks nothing. */
                            readonly property PanelRequests requests: item && item.requests ? item.requests : null
                        }

                        // Only the active tab's keyboard request counts.
                        Binding {
                            target: root
                            property: "tabWantsKeyboard"
                            value: body.requests ? body.requests.wantsKeyboard : false
                            when: page.shown
                            restoreMode: Binding.RestoreNone
                        }

                        Connections {
                            target: body.requests
                            function onDialogRequested(openDialog, afterClose) {
                                slide.closeThenRun(openDialog, afterClose);
                            }
                            function onReopenRequested() {
                                root.activeTab = root.tabIds.indexOf(page.tabId);
                                root.openPanel();
                            }
                        }
                    }
                }
            }

            Spine {
                id: spine
                x: parent.width - width
                y: 0
                width: 60
                height: parent.height
                tabs: root.tabs
                activeTab: root.activeTab
                onTabClicked: index => root.activeTab = index
            }
        }
    }

    // The icon flight sits above pillRect. It is clipped to the pill's own shape,
    // so no icon is ever seen outside the bar while the bar narrows or shrinks.
    Item {
        id: iconClip
        // Keeps the flying icons inside the bar.
        x: pillRect.x
        y: pillRect.y
        width: pillRect.width
        height: pillRect.height
        clip: true

        IconFlight {
            id: iconFlight
            x: -iconClip.x
            y: -iconClip.y
            width: root.width
            height: root.height
            tabs: root.tabs
            activeTab: root.activeTab
            elapsedMs: root.elapsedMs
            closing: root.closing
            startMs: root.widenMs
            dpr: root.dpr
            barHeight: root.pillHeight
            barCenterX: PixelGrid.snap(root.width / 2, root.dpr)
            // The spine's left edge and top edge once the pill is at full size (dashboard inset 1px).
            spineX: barCenterX + root.panelWidth / 2 - 1 - spine.width
            spineY: 1
            spineWidth: spine.width
            buttonSize: spine.buttonSize
            dashboardSlide: dashboardSlide.y
        }
    }

    // ---- Tab bodies, one per entry of `tabs`. ----

    Component {
        id: homeBody

        HomeTab {
            anchors.fill: parent
            tooltipLayer: dashboard
            panelOpen: root.panelReady
            // Tab area at rest: the panel minus the 1px inset, the spine and its seam.
            restSize: Qt.size(root.panelWidth - 2 - spine.width - 1, root.panelHeight - 2)
        }
    }

    Component {
        id: mediaBody
        MediaTab { anchors.fill: parent }
    }

    Component {
        id: systemBody
        SystemTab { anchors.fill: parent }
    }

    Component {
        id: codeBody
        CodeTab { anchors.fill: parent }
    }

    Component {
        id: calendarBody

        CalendarTab {
            anchors.fill: parent
            panelOpen: root.panelOpen
        }
    }

    Component {
        id: weatherBody
        WeatherTab { anchors.fill: parent }
    }

    Component {
        id: alertsBody
        AlertsTab { anchors.fill: parent }
    }

    // Tray popover, app menu and their click catcher. Fills the monitor, not the
    // window: the window is narrow at rest and grows around its center when a
    // layer opens. The rects are outside pillRect's clip.
    PillTrayLayers {
        id: trayLayers
        x: PixelGrid.snap((root.parent ? root.parent.width : 0) / 2 - width / 2 - root.x, root.dpr)
        y: -root.y
        width: Screen.width
        height: Screen.height
        items: root.trayItems
    }

    /** Exposes the pill's on-screen rectangle for the panel's input mask. */
    property alias maskX: pillRect.x
    property alias maskY: pillRect.y
    property alias maskWidth: pillRect.width
    property alias maskHeight: pillRect.height
}
