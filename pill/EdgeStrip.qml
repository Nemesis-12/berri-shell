import QtQuick

/**
 * The reveal strip of one screen edge (top or bottom). While a fullscreen or
 * maximized window covers the monitor, the panel at this edge is hidden and
 * only this thin strip takes input. The cursor on the strip reveals the panel;
 * it hides again 600 ms after the cursor left, never while `keepShown` holds.
 *
 * Place it in the window with the window size set; it sits centered on its
 * edge. EdgeWindow uses one strip per edge.
 */
Item {
    id: root

    /** The strip is on the bottom edge instead of the top edge. */
    property bool atBottom: false
    /** Size of the window (the whole monitor only while a panel is open). */
    property real windowWidth: 0
    property real windowHeight: 0
    /** A fullscreen or maximized window covers the monitor. */
    property bool covered: false
    /** The panel is open, closing or pointed at: the reveal must not end now. */
    property bool keepShown: false

    /** True while the panel is shown on purpose during fullscreen. Cleared by the hide timer or when fullscreen ends. */
    property bool revealed: false
    /** The panel is hidden only in fullscreen and only until it is revealed. */
    readonly property bool panelHidden: covered && !revealed

    readonly property int stripWidth: 400
    readonly property int stripHeight: 2

    x: Math.round((windowWidth - stripWidth) / 2)
    y: atBottom ? windowHeight - stripHeight : 0
    width: stripWidth
    height: stripHeight
    z: 10 // above the panel, which would otherwise take the hover

    HoverHandler {
        id: hover
        onHoveredChanged: if (hovered && root.covered) root.revealed = true
    }

    Timer {
        interval: 600
        running: root.revealed && root.covered && !root.keepShown && !hover.hovered
        onTriggered: root.revealed = false
    }
}
