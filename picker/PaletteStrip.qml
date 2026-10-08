import QtQuick
import "../logic/PixelGrid.js" as PixelGrid
import "../logic/Timeline.js" as Timeline
import qs.services

/**
 * The 6 theme swatches as ONE set of segments that morph between two
 * layouts (mock: "Berri Desktop v2.dc.html", `segs`, Spine `else` branch,
 * and the `pkFull` strip branch):
 *  - notch bars: separate bars, 2px gap, radius 1.5, 1px inner line in the
 *    foreground color at 24% opacity, sized 8x11 rest / 10x14 hover.
 *  - picker strip: one strip sized/positioned to land exactly on the
 *    focused theme card's own 6-color strip (stripWidth/stripHeight/
 *    stripBottom, set by the caller; default 196x133 sitting 47px above
 *    the panel bottom if the caller leaves them unset), segment i at
 *    x = -stripWidth/2 + i*stripWidth/6, no gaps, radius 10 only on the
 *    outer ends of segments 0 and 5, no inner line.
 *
 * `progress` (0 notch, 1 strip) is the only motion input. The caller drives it
 * in a straight line; every bar shows its own slice of it (spring curve).
 * bottom/height/radius/line-opacity use the first slice. Segment x/width use
 * a slice that starts i * staggerMs later, so the outer bars trail. Close is
 * the same path in reversed order because nothing here keeps its own time;
 * `closing` eases each slice out into rest. `spanMs` is the time one full morph takes, so the caller can size its window to match.
 *
 * Positions itself like the mock does: segments sit at an x offset from
 * this item's own horizontal center and a y offset from its own bottom
 * edge, so the caller should anchors.fill this to the picker rectangle
 * (whatever width/height that rectangle currently has).
 */
Item {
    id: root

    required property var colors

    /** 0 rest, 1 hover; only meaningful while openProgress is 0. */
    property real hoverProgress: 0
    /** Container height (px) at rest/hover, used only to center bars vertically before any morph. */
    property real restContainerHeight: 22
    property real hoverContainerHeight: 28

    /** 0 = notch bars, 1 = merged picker strip. The only motion input. */
    property real progress: 0
    /** True while the motion runs back to the notch bars: every step then eases out into rest. */
    property bool closing: false
    /** Time one bar needs to morph, and the delay between one bar and the next. */
    readonly property int morphMs: 480
    readonly property int staggerMs: 20
    /** Time for the whole morph, last bar included. */
    readonly property int spanMs: morphMs + (barCount - 1) * staggerMs
    readonly property real elapsedMs: progress * spanMs
    readonly property real openProgress: Timeline.springSlice(elapsedMs, 0, morphMs, closing)

    readonly property int barCount: 6
    readonly property int gap: 2
    readonly property real restBarWidth: 8
    readonly property real hoverBarWidth: 10
    readonly property real restBarHeight: 11
    readonly property real hoverBarHeight: 14

    // Overridable by the caller so the picker strip can land exactly on the
    // focused theme card's own color strip (see ThemeNotch.qml, which binds
    // these to ThemesCarousel's measured card-strip geometry). Defaults keep
    // the old mock-rounded numbers for any caller that doesn't override them.
    property real stripWidth: 196
    property real stripHeight: 133
    property real stripBottom: 47
    readonly property real stripSegWidth: stripWidth / barCount

    readonly property real barWidth: restBarWidth + (hoverBarWidth - restBarWidth) * hoverProgress
    readonly property real barHeight: restBarHeight + (hoverBarHeight - restBarHeight) * hoverProgress
    readonly property real barsTotalWidth: barCount * barWidth + (barCount - 1) * gap
    readonly property real notchContainerHeight: restContainerHeight + (hoverContainerHeight - restContainerHeight) * hoverProgress
    readonly property real notchBottom: (notchContainerHeight - barHeight) / 2

    readonly property real segBottom: notchBottom + (stripBottom - notchBottom) * openProgress
    readonly property real segHeight: barHeight + (stripHeight - barHeight) * openProgress
    readonly property real genRadius: 1.5 * (1 - openProgress)
    readonly property real outerRadius: 1.5 + (10 - 1.5) * openProgress
    readonly property real lineOpacity: 1 - openProgress

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    Repeater {
        id: repeater
        model: root.barCount

        delegate: Item {
            id: seg
            required property int index
            anchors.fill: parent

            // Bar i starts i * staggerMs after the first bar.
            readonly property real xwProgress: Timeline.springSlice(root.elapsedMs, index * root.staggerMs, root.morphMs, root.closing)

            readonly property real notchX: -root.barsTotalWidth / 2 + index * (root.barWidth + root.gap)
            readonly property real stripX: -root.stripWidth / 2 + index * root.stripSegWidth
            readonly property real segX: notchX + (stripX - notchX) * xwProgress
            readonly property real segW: root.barWidth + (root.stripSegWidth - root.barWidth) * xwProgress

            Rectangle {
                x: PixelGrid.snap(seg.width / 2 + seg.segX, root.dpr)
                y: PixelGrid.snap(seg.height - root.segBottom - root.segHeight, root.dpr)
                width: PixelGrid.snap(seg.segW, root.dpr)
                height: PixelGrid.snap(root.segHeight, root.dpr)
                color: root.colors[seg.index]

                topLeftRadius: seg.index === 0 ? root.outerRadius : root.genRadius
                bottomLeftRadius: seg.index === 0 ? root.outerRadius : root.genRadius
                topRightRadius: seg.index === root.barCount - 1 ? root.outerRadius : root.genRadius
                bottomRightRadius: seg.index === root.barCount - 1 ? root.outerRadius : root.genRadius

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: parent.radius
                    topLeftRadius: parent.topLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    bottomRightRadius: parent.bottomRightRadius
                    border.width: 1
                    border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.24)
                    opacity: root.lineOpacity
                }
            }
        }
    }
}
