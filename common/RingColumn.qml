import QtQuick

/**
 * A ring with its caption below. The ring sits centered in a box of
 * `boxHeight`, so captions line up under rings of different sizes. Put the
 * ring inside it and set `width` (the caption centers in it).
 */
Column {
    id: root

    property real boxHeight: 50
    property string caption: ""

    /** The ring (use `anchors.centerIn: parent`). */
    default property alias ring: box.data

    spacing: 6

    Item {
        id: box
        width: root.width
        height: root.boxHeight
    }

    MonoText {
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root.caption
        font.letterSpacing: 9 * 0.08
    }
}
