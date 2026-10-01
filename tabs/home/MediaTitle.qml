import QtQuick
import qs.services

/**
 * Big track title (mock 5C Media: 500 60px Plex Condensed). A title that fits
 * stays still, and so does any title while nothing plays. A longer title of a
 * playing track scrolls one pass, holds for `holdMs`, then scrolls again, behind
 * a soft edge fade. Scrolling runs only while the item is visible. When playing
 * stops, the pass stops at once and the title slides back to its start with a
 * short eased move, so the text never moves in one step in the middle of the title.
 */
Item {
    id: root

    property string text: ""
    property color fadeColor: Theme.card
    /** True while the track plays. The Media tab passes it in from MediaPlayer. */
    property bool playing: false

    /** The item reaches `bleed` px left of the text start so looping text fades out there. */
    readonly property real bleed: 10
    readonly property real gap: 48
    readonly property real textWidth: root.width - root.bleed
    readonly property bool overflows: measure.implicitWidth > root.textWidth
    readonly property int holdMs: 3000
    readonly property bool wantsScroll: root.playing && root.overflows && root.visible
    // True while the hold between two passes runs; the title rests at its start then.
    property bool holding: false

    // The one place that decides to start or stop the scroll. Every change of
    // wantsScroll, every new title and every end of a pass calls it.
    function updateScroll() {
        if (root.wantsScroll) {
            settle.stop()
            if (!scroll.running)
                scroll.start()
        } else if (scroll.running) {
            // The stop ends in onStopped, which calls this function again.
            scroll.stop()
        } else if (loop.x !== root.bleed) {
            // Move back to the start; the still title shows when this ends.
            settle.start()
        }
    }

    onWantsScrollChanged: root.updateScroll()
    // A new title starts at its start, with no move back.
    onTextChanged: {
        scroll.stop()
        settle.stop()
        loop.x = root.bleed
        root.updateScroll()
    }

    height: 60
    clip: true

    Text {
        id: measure
        visible: false
        text: root.text
        font.family: Theme.condensed
        font.weight: Font.Medium
        font.pixelSize: 60
        font.letterSpacing: -1.8
    }

    // Still title.
    Text {
        visible: !scroll.running && !settle.running
        x: root.bleed
        width: root.textWidth
        height: 60
        text: root.text
        color: Theme.fg
        font: measure.font
        lineHeightMode: Text.FixedHeight
        lineHeight: 60
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    // Scrolling title: two copies, shifted by one copy plus the gap.
    Row {
        id: loop
        visible: scroll.running || settle.running
        x: root.bleed
        height: 60
        spacing: root.gap

        Repeater {
            model: 2

            Text {
                height: 60
                text: root.text
                color: Theme.fg
                font: measure.font
                lineHeightMode: Text.FixedHeight
                lineHeight: 60
                verticalAlignment: Text.AlignVCenter
            }
        }

        // One pass moves the second copy onto the start spot, so the reset to the
        // start is not visible. The hold follows the pass. A stop in the middle of
        // a pass leaves the text where it is; `settle` then moves it back. A stop
        // in the hold needs no move: the second copy is on the start spot already.
        SequentialAnimation {
            id: scroll
            NumberAnimation {
                target: loop
                property: "x"
                from: root.bleed
                to: root.bleed - (measure.implicitWidth + root.gap)
                duration: Math.max(1000, root.text.length * 360)
            }
            ScriptAction { script: root.holding = true }
            PauseAnimation { duration: root.holdMs }
            onStopped: {
                if (root.holding)
                    loop.x = root.bleed
                root.holding = false
                root.updateScroll()
            }
        }

        // Eased move back to the start after a stop in the middle of a pass.
        NumberAnimation {
            id: settle
            target: loop
            property: "x"
            to: root.bleed
            duration: Theme.stateMs
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        visible: root.overflows
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: root.bleed
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.fadeColor }
            GradientStop { position: 1; color: Qt.alpha(root.fadeColor, 0) }
        }
    }

    Rectangle {
        visible: root.overflows
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 28
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.fadeColor, 0) }
            GradientStop { position: 1; color: root.fadeColor }
        }
    }
}
