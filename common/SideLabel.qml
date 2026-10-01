import QtQuick
import qs.services

/**
 * Dim mono label that reads from bottom to top (mock: writing-mode vertical-rl
 * with rotate(180deg)). The item is `width` wide and as tall as the text; the
 * first letter sits at the bottom. `width` is one text line unless set.
 * `textX` moves the turned text across the item (0 for a line that fills
 * the width). Read `lineHeight` and `textBaseline` to center the text or to put
 * its baseline at a mock position, for example
 * `textX: (width - lineHeight) / 2` or `textX: 7.875 - textBaseline`.
 */
Item {
    id: root

    property string text: ""
    property real size: 9
    property real spacing: 1.62
    property color tone: Theme.dim
    property int weight: Font.Medium
    property int renderType: Text.QtRendering
    property real textX: 0

    /** Height of one text line (the width of the turned label). */
    readonly property real lineHeight: label.implicitHeight
    /** Baseline offset of the text, measured from the top of the unturned line. */
    readonly property real textBaseline: label.baselineOffset

    width: label.implicitHeight
    height: label.implicitWidth

    MonoText {
        id: label
        text: root.text
        color: root.tone
        font.pixelSize: root.size
        font.weight: root.weight
        font.letterSpacing: root.spacing
        renderType: root.renderType
        rotation: -90
        transformOrigin: Item.TopLeft
        x: root.textX
        y: root.height
    }
}
