import QtQuick
import QtQuick.Window
import "../logic/PixelGrid.js" as PixelGrid
import qs.common

/**
 * The base of the theme and wallpaper carousels: a row of cards that slides
 * so the focused card stays centered. It owns the viewport width, the focus
 * rule (move by `delta` cards, clamped to `count`) and the slide.
 *
 * Use it as the root of a carousel. Put the cards inside it (they go into the
 * row). Set `count`, `cardWidth`, `cardGap` and `trackHeight`.
 */
Item {
    id: root

    /** Index of the focused card. */
    property int focusIndex: 0

    /** How many cards the row holds. */
    property int count: 0

    property int cardWidth: 0
    property int cardGap: 0
    readonly property int cardStep: cardWidth + cardGap

    /** Height of the row. */
    property int trackHeight: 0

    // The picker body's 900px frame minus its 18px*2 side padding.
    readonly property int viewportWidth: 864

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)

    /** The cards of the carousel. */
    default property alias cards: row.data

    /** Moves focus by `delta` cards, clamped to the first and last card. */
    function moveFocus(delta) {
        if (root.count === 0) return;
        root.focusIndex = Math.max(0, Math.min(root.count - 1, root.focusIndex + delta));
    }

    clip: true

    Item {
        id: track
        width: row.width
        height: root.trackHeight
        anchors.verticalCenter: parent.verticalCenter
        // Centers the focused card: -(focusIndex * step - (viewport - card) / 2).
        x: PixelGrid.snap(-(root.focusIndex * root.cardStep - (root.viewportWidth - root.cardWidth) / 2), root.dpr)
        Behavior on x {
            SpringMotion {
                duration: 500
            }
        }

        Row {
            id: row
            spacing: root.cardGap
        }
    }
}
