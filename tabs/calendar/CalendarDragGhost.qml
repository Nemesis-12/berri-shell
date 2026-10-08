import QtQuick
import qs.common
import qs.services

/**
 * Drag ghost of the calendar: a translucent copy of the chip or row that
 * follows the pointer. The tab calls pickUp() when a drag starts, moveTo()
 * while it runs and flyTo() on release; the ghost then fades while it arrives.
 */
Item {
    id: root

    property var info: ({ shape: "chip", title: "", meta: "", done: false, tint: "white" })
    readonly property bool isRow: info.shape === "row"
    readonly property color tint: info.tint

    z: 100
    opacity: 0
    visible: opacity > 0
    enabled: false

    Rectangle {
        anchors.fill: parent
        color: root.isRow ? Theme.raised : Theme.card
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.15)
        visible: !root.isRow
    }

    Rectangle {
        width: 2
        height: parent.height
        color: root.tint
    }

    Text {
        textFormat: Text.PlainText
        x: root.isRow ? 14 : 6
        y: root.isRow ? 8 : Math.round((root.height - height) / 2)
        width: root.width - x - 6
        text: root.info.title
        elide: Text.ElideRight
        font.family: Theme.condensed
        font.pixelSize: root.isRow ? 14 : 10
        font.weight: Font.Medium
        font.strikeout: root.info.done
        color: root.info.done ? Theme.mute : (root.isRow ? Theme.fg : Theme.fg2)
    }

    MonoText {
        visible: root.isRow
        x: 14
        y: 8 + 14 + 4
        width: root.width - 20
        text: root.info.meta || ""
        elide: Text.ElideRight
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 0.36
        color: Theme.dim
    }

    /** Shows a copy of the dragged item. `info` has shape, title, meta, done, tint, width and height. */
    function pickUp(info) {
        settle.stop();
        root.info = info;
        root.opacity = 0.8;
        root.width = info.width;
        root.height = info.height;
    }

    /** Puts the ghost at whole-pixel position (x, y) in the tab. */
    function moveTo(x, y) {
        root.x = x;
        root.y = y;
    }

    /** Moves to (x, y) and fades out. */
    function flyTo(x, y) {
        settleX.to = x;
        settleY.to = y;
        settle.restart();
    }

    ParallelAnimation {
        id: settle

        StandardMotion {
            id: settleX
            target: root
            property: "x"
            duration: 220
        }
        StandardMotion {
            id: settleY
            target: root
            property: "y"
            duration: 220
        }
        StandardMotion {
            target: root
            property: "opacity"
            to: 0
            duration: 220
        }
    }
}
