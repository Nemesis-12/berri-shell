import QtQuick
import qs.common
import qs.services

/**
 * A small floating card in the mock's popover style (raised fill, 1px
 * border, soft shadow). It fades and rises in from the top while `open`
 * turns true; closing plays the same motion backwards. Put content in it;
 * set its width and height.
 */
Item {
    id: root

    property bool open: false
    property alias contentItem: card

    /** Content goes into the card, inside its border. */
    default property alias content: card.data

    /** Scale pivot: Item.Top (centered popover) or Item.TopLeft (menu). */
    property int pivot: Item.Top

    visible: opacity > 0.001
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.listMs } }

    // 0 = closed pose (6px up, 97% size), 1 = open pose.
    property real progress: open ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: 380
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.springCurve
        }
    }
    transform: [
        Scale {
            origin.x: root.pivot === Item.Top ? root.width / 2 : 0
            origin.y: 0
            xScale: 0.97 + 0.03 * root.progress
            yScale: 0.97 + 0.03 * root.progress
        },
        Translate { y: -6 * (1 - root.progress) }
    ]

    PanelShadow {
        target: card
        restOffset: 18
        restStrength: 0.45
        restBlur: 44
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: PillTrayStyle.popoverRadius
        color: Theme.raised
        border.width: 1
        border.color: Theme.border
    }
}
