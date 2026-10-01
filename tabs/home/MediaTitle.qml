import QtQuick
import qs.services

/**
 * Big track title (mock 5C Media: 500 60px Plex Condensed). A title that fits
 * stays still, and so does any title while nothing plays. A longer title of a
 * playing track scrolls one pass, holds for `holdMs`, then scrolls again, behind
 * a soft edge fade. Scrolling runs only while the item is visible. When playing
 * stops, the pass in progress ends first, so the text never jumps mid-title.
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

    onWantsScrollChanged: {
        if (root.wantsScroll) {
            if (!scroll.running)
                scroll.start()
        } else if (!root.visible || root.holding) {
            scroll.stop()
        }
        // Otherwise the pass in progress ends first, then the title rests.
    }
    // A new title starts a new pass.
    onTextChanged: if (scroll.running) scroll.stop()

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
        visible: !scroll.running
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

    // Looping title: two copies, shifted by one copy plus the gap.
    Row {
        id: loop
        visible: scroll.running
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
        // start is not visible. The hold follows the pass. Every end (also a stop)
        // resets the position, then a new run starts if scrolling is still wanted.
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
                root.holding = false
                loop.x = root.bleed
                if (root.wantsScroll)
                    scroll.start()
            }
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
