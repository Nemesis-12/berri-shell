import QtQuick
import "../../logic/Times.js" as Times
import qs.common
import qs.services

/**
 * Time card of the media tab: the elapsed time, the length and a scrubber.
 * Press or drag the scrubber to seek; the card only emits `seekRequested`
 * and the tab sends it to MediaPlayer. The tab sets the position and size,
 * and passes the playback values it reads from MediaPlayer. A position below
 * 0 means unknown and a length of 0 means unknown: the card then shows no
 * such time.
 */
Rectangle {
    id: root

    required property real displayPosition
    required property real length
    required property real progress
    required property bool isPlaying
    required property bool canSeek

    /** The scrubber was pressed or dragged to `ratio` (0 to 1) of its width. */
    signal seekRequested(real ratio)

    /** True while the scrubber is pressed; the tab then keeps the shown position steady. */
    readonly property bool scrubbing: scrub.pressed

    height: 150
    color: Theme.card

    SideLabel {
        x: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        text: "TIME"
    }

    Item {
        id: readout
        x: 12 + 9 + 12
        width: parent.width - x - 16
        height: 61
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14 + 14 + 14

        Text {
            textFormat: Text.PlainText
            id: elapsed
            width: Math.min(implicitWidth, Math.max(0, readout.width - (total.visible ? total.width + 8 : 0)))
            elide: Text.ElideRight
            height: 61
            text: root.displayPosition >= 0 ? Times.minutesSeconds(root.displayPosition) : ""
            color: Theme.fg
            font.family: Theme.condensed
            font.weight: Font.Medium
            font.pixelSize: 76
            font.letterSpacing: -2.28
            lineHeightMode: Text.FixedHeight
            lineHeight: 61
            verticalAlignment: Text.AlignVCenter
        }

        MonoText {
            id: total
            objectName: "total"
            visible: root.displayPosition >= 0 && root.length > 0
            x: elapsed.width + 8
            anchors.baseline: elapsed.baseline
            anchors.baselineOffset: -19
            text: "/ " + Times.minutesSeconds(root.length)
            color: Theme.dim
            font.pixelSize: 12
        }
    }

    // Scrubber: 4px track, 12px square handle. Press or drag to seek.
    Item {
        id: scrub
        x: readout.x
        width: readout.width
        height: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14

        property bool pressed: seekArea.pressed

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            y: 8
            height: 4
            color: Theme.border

            Rectangle {
                id: trackFill
                height: parent.height
                width: parent.width * root.progress
                color: Theme.accentLight

                Behavior on width {
                    enabled: root.isPlaying && !scrub.pressed
                    NumberAnimation { duration: 1000; easing.type: Easing.Linear }
                }
            }

            Rectangle {
                x: trackFill.width - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                color: Theme.fg
            }
        }

        MouseArea {
            id: seekArea
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            enabled: root.canSeek
            cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

            function seek(mouseX) {
                const ratio = Math.max(0, Math.min(1, mouseX / width));
                root.seekRequested(ratio);
            }
            onPressed: mouse => seek(mouse.x)
            onPositionChanged: mouse => { if (pressed) seek(mouse.x); }
        }
    }
}
