import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.tabs.system

/**
 * One full-monitor overlay window for a panel that sits at the top or bottom
 * edge: the top pill and the bottom theme notch.
 *
 * At rest the window passes input through everywhere except the panel shape
 * (and the pop-up card, if any). While a fullscreen or maximized window covers
 * the monitor the panel is hidden and only a thin strip on the screen edge takes
 * input. The cursor on the strip reveals the panel; it hides again 600 ms after
 * the cursor left it, never while the panel is open. While the panel is open the
 * whole monitor takes input and is dimmed; a click on the dim layer emits dimClicked.
 *
 * The panel and its pop-up go inside this window as children. The parent sets
 * the panel shape (panelX..panelHeight) and the state flags.
 */
PanelWindow {
    id: root

    /** The strip and the panel are at the bottom edge instead of the top. */
    property bool atBottom: false
    /** Layer-shell name of this window. */
    property string layerName: ""

    /** Input shape of the panel at rest, in window coordinates. */
    property real panelX: 0
    property real panelY: 0
    property real panelWidth: 0
    property real panelHeight: 0
    /** The panel is open: the whole monitor takes input. */
    property bool panelOpen: false
    /** The panel is open, closing or pointed at: the reveal must not end now. */
    property bool keepShown: false
    /** The panel needs the keyboard (a text field is in use). */
    property bool wantsKeyboard: false
    /** Dims the monitor behind the panel. */
    property bool dimmed: false
    /** Optional pop-up card (PillPopup) that takes input while it shows. */
    property var card: null

    /** The dim layer was clicked. */
    signal dimClicked()
    /** A fullscreen or maximized window just started to cover this monitor. */
    signal fullscreenStarted()

    /** True while a fullscreen or maximized window covers this monitor. */
    readonly property bool screenHasFullscreenWindow: FullscreenState.coversMonitor(root.screen)
    /**
     * True while the panel is shown on purpose during fullscreen: the cursor
     * touched the edge strip. Cleared by the hide timer or when fullscreen ends.
     */
    property bool revealed: false
    /** The panel is hidden only in fullscreen and only until it is revealed. */
    readonly property bool panelHidden: screenHasFullscreenWindow && !revealed

    readonly property int stripWidth: 400
    readonly property int stripHeight: 2
    readonly property real stripX: Math.round((width - stripWidth) / 2)
    readonly property real stripY: atBottom ? height - stripHeight : 0

    default property alias content: panelContent.data

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.layerName

    // The window takes no keyboard focus at rest. It asks for it while the panel
    // needs it, so that a click on a text field gets the keyboard: Hyprland gives
    // on-demand focus only to a click that lands while the layer already asks.
    WlrLayershell.keyboardFocus: root.wantsKeyboard
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Covers the whole monitor so the dim layer and the open panel have room;
    // the mask keeps input pass-through everywhere else at rest.
    anchors { top: true; left: true; right: true; bottom: true }

    /** Closes the panel at once (parent reacts to the signal) if fullscreen takes over. A reveal never runs this. */
    onScreenHasFullscreenWindowChanged: {
        root.revealed = false;
        if (root.screenHasFullscreenWindow) {
            root.fullscreenStarted();
            // Clear an unfinished dim fade too, including one already closing.
            dimFade.stop();
            dimLayer.opacity = Qt.binding(function () { return root.dimmed ? 0.32 : 0; });
        }
    }

    // Input, by state: hidden = only the strip; open = the whole monitor;
    // otherwise the panel shape, plus the strip in fullscreen so the cursor can
    // travel from the edge to the panel. The pop-up card is written once.
    mask: Region {
        x: root.panelHidden ? root.stripX : root.panelOpen ? 0 : root.panelX
        y: root.panelHidden ? root.stripY : root.panelOpen ? 0 : root.panelY
        width: root.panelHidden ? root.stripWidth : root.panelOpen ? root.width : root.panelWidth
        height: root.panelHidden ? root.stripHeight : root.panelOpen ? root.height : root.panelHeight

        Region {
            x: root.stripX
            y: root.stripY
            width: root.screenHasFullscreenWindow ? root.stripWidth : 0
            height: root.screenHasFullscreenWindow ? root.stripHeight : 0
        }
        Region {
            x: root.card ? root.card.cardX : 0
            y: root.card ? root.card.cardY : 0
            width: root.card ? root.card.cardWidth : 0
            height: root.card ? root.card.cardHeight : 0
        }
    }

    /** Reports the cursor on the edge strip; it reveals the panel. */
    Item {
        x: root.stripX
        y: root.stripY
        width: root.stripWidth
        height: root.stripHeight
        z: 10 // above the panel, which would otherwise take the hover
        HoverHandler {
            id: stripHover
            onHoveredChanged: if (hovered && root.screenHasFullscreenWindow) root.revealed = true
        }
    }

    /** Hides the revealed panel 600 ms after the cursor left it, never while it must stay. */
    Timer {
        interval: 600
        running: root.revealed && root.screenHasFullscreenWindow && !root.keepShown && !stripHover.hovered
        onTriggered: root.revealed = false
    }

    /** Dims the rest of the monitor while the panel is open or closing; a click closes it. */
    Rectangle {
        id: dimLayer
        anchors.fill: parent
        color: "black"
        opacity: root.dimmed ? 0.32 : 0

        Behavior on opacity {
            enabled: !root.panelHidden
            NumberAnimation {
                id: dimFade
                duration: 450
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.springCurve
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dimClicked()
        }
    }

    // The panel and its pop-up, above the dim layer.
    Item {
        id: panelContent
        anchors.fill: parent
    }
}
