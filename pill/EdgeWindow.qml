import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

/**
 * The one overlay window of a monitor. It holds the top pill (with its
 * pop-up card) and the bottom theme notch.
 *
 * At rest the window is narrow (`restWidth`, full height) and passes input
 * through everywhere except the pill shape, the notch shape and the pop-up
 * card. While a panel is open, closing or still dimming, the window grows to
 * the whole monitor, the monitor is dimmed and takes input, and a click on the
 * dim layer emits dimClicked. The window grows around its center, so the panels
 * keep their place on the screen.
 *
 * While a fullscreen or maximized window covers the monitor, each panel is
 * hidden and only a thin strip on its screen edge takes input (see EdgeStrip).
 *
 * The panels go inside this window as children, bottom one first. The parent
 * sets the panel shapes (topX..bottomHeight) and the state flags.
 */
PanelWindow {
    id: root

    /** Layer-shell name of this window. */
    property string layerName: ""
    /** Width of the window at rest, in logical pixels. Wide enough for the hovered pill, its shadow and the pop-up card. */
    property real restWidth: 640

    /** Input shape of the top panel at rest, in window coordinates. */
    property real topX: 0
    property real topY: 0
    property real topWidth: 0
    property real topHeight: 0
    /** Input shape of the bottom panel at rest, in window coordinates. */
    property real bottomX: 0
    property real bottomY: 0
    property real bottomWidth: 0
    property real bottomHeight: 0
    /** A panel is open: the whole monitor takes input. */
    property bool panelOpen: false
    /** The top panel is open, closing or pointed at: its reveal must not end now. */
    property bool topKeepShown: false
    /** The bottom panel is open, closing or pointed at: its reveal must not end now. */
    property bool bottomKeepShown: false
    /** A panel needs the keyboard. */
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
    /** The top or bottom panel is shown on purpose during fullscreen (the cursor touched its strip). */
    property alias topRevealed: topEdge.revealed
    property alias bottomRevealed: bottomEdge.revealed
    /** A panel is hidden only in fullscreen and only until it is revealed. */
    readonly property bool topHidden: topEdge.panelHidden
    readonly property bool bottomHidden: bottomEdge.panelHidden

    /** True while the window covers the whole monitor: a panel is open or the dim layer still shows. */
    readonly property bool expanded: panelOpen || dimLayer.opacity > 0.001

    default property alias content: panelContent.data

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.layerName

    // The window takes no keyboard focus at rest. It asks for it while a panel
    // needs it, so that a click on a text field gets the keyboard: Hyprland gives
    // on-demand focus only to a click that lands while the layer already asks.
    WlrLayershell.keyboardFocus: root.wantsKeyboard
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Full height always (the bottom panel sits on the bottom edge). Narrow at
    // rest and centered by the compositor; left and right anchors make it as wide
    // as the monitor while expanded. Its buffers are small at rest.
    implicitWidth: root.restWidth
    anchors { top: true; bottom: true; left: root.expanded; right: root.expanded }

    /** Closes the panels at once (parent reacts to the signal) if fullscreen takes over. A reveal never runs this. */
    onScreenHasFullscreenWindowChanged: {
        topEdge.revealed = false;
        bottomEdge.revealed = false;
        if (root.screenHasFullscreenWindow) {
            root.fullscreenStarted();
            // Clear an unfinished dim fade too, including one already closing.
            dimFade.stop();
            dimLayer.opacity = Qt.binding(function () { return root.dimmed ? 0.32 : 0; });
        }
    }

    // Input, by state: a panel open = the whole monitor; otherwise each panel
    // shape that is not hidden, plus each strip in fullscreen so the cursor can
    // travel from the edge to the panel. The pop-up card is written once.
    mask: Region {
        x: 0
        y: 0
        width: root.panelOpen ? root.width : 0
        height: root.panelOpen ? root.height : 0

        Region {
            x: root.topX
            y: root.topY
            width: root.panelOpen || root.topHidden ? 0 : root.topWidth
            height: root.panelOpen || root.topHidden ? 0 : root.topHeight
        }
        Region {
            x: root.bottomX
            y: root.bottomY
            width: root.panelOpen || root.bottomHidden ? 0 : root.bottomWidth
            height: root.panelOpen || root.bottomHidden ? 0 : root.bottomHeight
        }
        Region {
            x: topEdge.x
            y: topEdge.y
            width: root.screenHasFullscreenWindow ? topEdge.width : 0
            height: root.screenHasFullscreenWindow ? topEdge.height : 0
        }
        Region {
            x: bottomEdge.x
            y: bottomEdge.y
            width: root.screenHasFullscreenWindow ? bottomEdge.width : 0
            height: root.screenHasFullscreenWindow ? bottomEdge.height : 0
        }
        Region {
            x: root.card ? root.card.cardX : 0
            y: root.card ? root.card.cardY : 0
            width: root.card ? root.card.cardWidth : 0
            height: root.card ? root.card.cardHeight : 0
        }
    }

    EdgeStrip {
        id: topEdge
        monitorWidth: root.width
        monitorHeight: root.height
        covered: root.screenHasFullscreenWindow
        keepShown: root.topKeepShown
    }

    EdgeStrip {
        id: bottomEdge
        atBottom: true
        monitorWidth: root.width
        monitorHeight: root.height
        covered: root.screenHasFullscreenWindow
        keepShown: root.bottomKeepShown
    }

    /** Dims the rest of the monitor while a panel is open or closing; a click closes it. */
    Rectangle {
        id: dimLayer
        anchors.fill: parent
        color: "black"
        opacity: root.dimmed ? 0.32 : 0
        // Nothing to draw or hit while clear.
        visible: opacity > 0.001

        Behavior on opacity {
            enabled: !root.topHidden && !root.bottomHidden
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

    // The panels and the pop-up, above the dim layer.
    Item {
        id: panelContent
        anchors.fill: parent
    }
}
