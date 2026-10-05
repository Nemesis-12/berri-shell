import QtQuick
import qs.common
import qs.services

/**
 * A full-height fill meter for one limit (mock 5C limit): the fill rises from
 * the bottom to `percent`; the big number, the time left and the vertical
 * name are drawn twice, once in the text color and once in the on-accent
 * color clipped to the fill, so they stay readable on both sides of the edge.
 * `percent` below zero means unknown: empty meter, "--".
 */
Item {
    id: root

    property string name: ""
    property real percent: -1
    /** Time left, like "2H 14M" (already upper case), or "--". */
    property string timeLeft: "--"

    readonly property real targetShare: Math.max(0, Math.min(100, root.percent)) / 100

    // One animated share (0..1) drives the fill and the clipped copy of the
    // text; the height follows the live layout size and never exceeds it.
    property real fillShare: targetShare
    readonly property real fillHeight: Math.max(0, Math.min(root.height, fillShare * root.height))
    clip: true
    Behavior on fillShare {
        StandardMotion { duration: 450 }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.card
    }

    Rectangle {
        width: parent.width
        y: parent.height - height
        height: root.fillHeight
        color: Theme.accentLight
    }

    // One drawing of the text block; `tone` is the color it is drawn in.
    component Readout: Item {
        id: readout
        property color tone: Theme.fg
        width: root.width
        height: root.height

        Column {
            x: 10
            y: 12
            spacing: 7

            Row {
                spacing: 2
                Item {
                    width: number.implicitWidth
                    height: 32
                    CodeValue {
                        id: number
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.percent >= 0 ? String(Math.round(root.percent)) : "--"
                        color: readout.tone
                        font.pixelSize: 40
                        font.letterSpacing: -1.2
                    }
                }
                CondensedText {
                    text: "%"
                    color: readout.tone
                    font.pixelSize: 12
                }
            }

            CodeValue {
                id: leftText
                value: root.timeLeft + "\nLEFT"
                color: readout.tone
                font.family: Theme.mono
                font.pixelSize: 9
                font.letterSpacing: 0.36
                lineHeight: 1.4
            }
        }

        SideLabel {
            width: size
            textX: (width - lineHeight) / 2
            x: 10
            y: parent.height - 12 - height
            text: root.name.toUpperCase()
            spacing: 1.62
            weight: Font.DemiBold
            tone: readout.tone
        }
    }

    Readout { tone: Theme.fg }

    Item {
        width: parent.width
        y: parent.height - height
        height: root.fillHeight
        clip: true

        Readout {
            tone: Theme.onAccent
            width: root.width
            height: root.height
            y: parent.height - root.height
        }
    }
}
