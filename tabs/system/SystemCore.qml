import QtQuick
import "../../logic/PixelGrid.js" as PixelGrid
import qs.common
import qs.services

/**
 * One per-core meter cell: a fill that rises from the bottom with the load,
 * the load number at the top left and the core name at the bottom left. The
 * text turns dark where the fill covers it (drawn twice, the second copy
 * clipped to the fill; the mock does this with a difference blend).
 */
Item {
    id: root

    /** Core number shown as "C0". */
    property int core: 0

    /** 0 to 100. */
    property real load: 0

    readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)
    property real level: 0

    // Follows `load` only for changes of a pixel or more; see SystemMeter.
    onLoadChanged: {
        if (Math.abs(load - level) / 100 * height >= 1 || load === 0) level = load;
    }

    Behavior on level {
        StandardMotion {
            duration: Theme.stateMs
        }
    }

    readonly property real fillHeight: PixelGrid.snap(level / 100 * height, dpr)

    // Channel-wise |a - b|, the colour a difference blend gives.
    function difference(a, b) {
        return Qt.rgba(Math.abs(a.r - b.r), Math.abs(a.g - b.g), Math.abs(a.b - b.b), 1);
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.card
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.fillHeight
        color: Theme.accentLight
    }

    SystemText {
        x: 9
        lineTop: 10
        font.pixelSize: 20
        text: Math.round(root.load)
        color: root.difference(Theme.fg, Theme.card)
    }

    SystemText {
        x: 9
        mono: true
        lineTop: root.height - 18
        font.pixelSize: 9
        font.weight: Font.DemiBold
        font.letterSpacing: 9 * 0.1
        text: "C" + root.core
        color: Theme.dim
    }

    // Copies of both texts in their over-the-fill colours, shown only inside the fill.
    Item {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.fillHeight
        clip: true

        SystemText {
            x: 9
            lineTop: 10 - (root.height - root.fillHeight)
            font.pixelSize: 20
            text: Math.round(root.load)
            color: root.difference(Theme.fg, Theme.accentLight)
        }

        SystemText {
            x: 9
            mono: true
            lineTop: root.height - 18 - (root.height - root.fillHeight)
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 9 * 0.1
            text: "C" + root.core
            color: Theme.onAccent
        }
    }
}
