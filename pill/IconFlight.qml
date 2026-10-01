import QtQuick
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/Timeline.js" as Timeline
import qs.common
import qs.services

/**
 * The tab icons that fly between the bar and the spine while the pill opens
 * (ticket 07). One square per tab: a centered row in the bar at the start,
 * the spine's own buttons at the end. The square of the active tab is the
 * accent one; it becomes the spine's active button.
 *
 * Every value comes from `elapsedMs`, the time since the open started. Close
 * plays `elapsedMs` backwards, so the flight runs in reversed order, and each
 * step eases out into rest (`closing`, see Timeline.js). A square
 * starts `startMs` after the open (when the pill is wide enough), the last
 * square to leave the row starts first, and all squares fade out at the end so
 * the real spine shows. `endMs` is when the flight is over.
 */
Item {
    id: root

    /** One entry per tab, in spine order; `icon` is the Lucide name. */
    required property var tabs
    required property int activeTab
    /** Time since the open started, in ms. */
    required property real elapsedMs
    /** True while the motion runs toward the bar: every step then eases out into rest. */
    required property bool closing
    /** When the squares start to fly, in ms after the open started. */
    required property int startMs
    required property real dpr
    /** Height of the bar, where the row sits. */
    required property real barHeight
    /** Horizontal center of the bar (already on the pixel grid). */
    required property real barCenterX
    /** Left edge and top edge of the spine's first button. */
    required property real spineX
    required property real spineY
    required property real spineWidth
    required property real buttonSize
    /** Vertical offset of the dashboard while it slides in; the squares follow it once they fly. */
    required property real dashboardSlide

    readonly property int fadeInDelayMs: 100
    readonly property int fadeInMs: 200
    readonly property int flightMs: 500
    readonly property int staggerMs: 18
    readonly property int colorMs: 400
    readonly property int fadeOutDelayMs: 660
    readonly property int fadeOutMs: 180

    /** When the squares start to fade out; from here on they hide the real spine. */
    readonly property int fadeOutStartMs: startMs + fadeOutDelayMs

    /** Time of the last frame of the flight. */
    readonly property int endMs: fadeOutStartMs + fadeOutMs

    /** While closing, every flight step starts this long after the open's last flight step ended, so the first square leaves at once (the fade-out of the squares is not played back). */
    /** The time at which the close of the squares is at rest: the fade-in of the squares is the last step of the close. */
    readonly property int closeEndMs: startMs + closeLagMs - fadeInMs

    readonly property int closeLagMs: endMs - (startMs + (tabs.length - 1) * staggerMs + flightMs)

    readonly property real rowSize: barHeight - 8
    readonly property int rowGap: 4
    readonly property real rowWidth: tabs.length * rowSize + (tabs.length - 1) * rowGap
    readonly property real rowX: barCenterX - rowWidth / 2
    readonly property real rowY: (barHeight - rowSize) / 2

    /** 0..1 opacity of every square: fades in at the start, out at the end. */
    readonly property real opacityNow: Timeline.fadeSlice(elapsedMs, fadeInDelayMs, fadeInMs, closing, startMs + closeLagMs)
        - Timeline.fadeSlice(elapsedMs, fadeOutStartMs, fadeOutMs, closing)

    visible: opacityNow > 0.001


    /** Color between two colors, per channel (the same blend as a color animation). */
    function mix(from, to, amount) {
        return Qt.rgba(from.r + (to.r - from.r) * amount, from.g + (to.g - from.g) * amount,
            from.b + (to.b - from.b) * amount, from.a + (to.a - from.a) * amount);
    }

    Repeater {
        model: root.tabs

        delegate: Rectangle {
            id: square
            required property var modelData
            required property int index

            readonly property bool active: index === root.activeTab

            // Targets are fixed numbers from the layout, not the live position of
            // the real button: that one moves while the pill grows, so a square
            // aimed at it would drift instead of flying in a straight line.
            readonly property real rowLeft: root.rowX + index * (root.rowSize + root.rowGap)
            readonly property real finalTop: root.spineY + index * root.buttonSize

            // The last square leaves the row first, so paths never cross. On close
            // the order reverses by itself.
            readonly property real flight: Timeline.springSlice(root.elapsedMs,
                root.startMs + (root.tabs.length - 1 - index) * root.staggerMs, root.flightMs, root.closing,
                root.startMs + (root.tabs.length - 1 - index) * root.staggerMs + root.flightMs + root.closeLagMs)
            readonly property real shape: Timeline.springSlice(root.elapsedMs, root.startMs, root.flightMs, root.closing,
                root.startMs + root.flightMs + root.closeLagMs)
            readonly property real tintPhase: root.closing
                ? Timeline.closeSlice(root.elapsedMs, root.startMs, root.colorMs, root.startMs + root.colorMs + root.closeLagMs)
                : Timeline.slice(root.elapsedMs, root.startMs, root.colorMs)
            readonly property real tint: root.closing ? 1 - Theme.easeOut(1 - tintPhase) : Theme.easeOut(tintPhase)

            // While a square and the real spine button are both on screen, the
            // dashboard slides; the square follows it to stay on the button.
            readonly property real slideOffset: root.elapsedMs >= root.startMs ? root.dashboardSlide : 0

            x: PixelGrid.snap(rowLeft + (root.spineX - rowLeft) * flight, root.dpr)
            y: PixelGrid.snap(root.rowY + (finalTop - root.rowY) * flight + slideOffset, root.dpr)
            width: PixelGrid.snap(root.rowSize + (root.spineWidth - root.rowSize) * shape, root.dpr)
            height: PixelGrid.snap(root.rowSize + (root.buttonSize - root.rowSize) * shape, root.dpr)
            radius: 5 * (1 - shape)
            opacity: root.opacityNow
            // The other squares become opaque stand-ins for their buttons, so the
            // real button never shows through during the handoff.
            color: active ? root.mix(Theme.accent, Theme.card, tint)
                          : Qt.rgba(Theme.shell.r, Theme.shell.g, Theme.shell.b, tint)

            // The active button keeps a 2px accent edge on its left side.
            Rectangle {
                visible: square.active
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 2
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, square.tint)
            }

            // The icon grows with the flight, 16px in the row to 19px in the spine.
            Icon {
                anchors.centerIn: parent
                name: square.modelData.icon
                size: PixelGrid.snap(16 + 3 * square.flight, root.dpr)
                strokeWidth: 1.5
                color: square.active ? root.mix(Theme.onAccent, Theme.accentLight, square.tint) : Theme.dim
            }
        }
    }
}
