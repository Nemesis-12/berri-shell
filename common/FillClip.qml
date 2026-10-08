import QtQuick

/**
 * Shows a copy of a meter's content only inside its fill. Put it in the
 * meter, which must be a clip box of its own. The fill grows from the bottom
 * edge. Children use the coordinates of the whole meter: they stay in place
 * while `fillHeight` changes, so a text drawn in a second color turns
 * only where the fill covers it.
 */
Item {
    id: root

    /** Height of the fill, from the bottom edge of the parent. */
    property real fillHeight: 0

    /** The meter content, drawn in the coordinates of the whole parent. */
    default property alias content: frame.data

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: fillHeight
    clip: true

    Item {
        id: frame
        y: root.height - root.parent.height
        width: root.width
        height: root.parent.height
    }
}
