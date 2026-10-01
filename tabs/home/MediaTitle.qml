import QtQuick
import qs.services

/**
 * Big track title (mock 5C Media: 500 60px Plex Condensed). A title that fits
 * stays still; a longer one loops behind a soft edge fade. The loop runs only
 * while the item is visible.
 */
Item {
    id: root

    property string text: ""
    property color fadeColor: Theme.card

    /** The item reaches `bleed` px left of the text start so looping text fades out there. */
    readonly property real bleed: 10
    readonly property real gap: 48
    readonly property real textWidth: root.width - root.bleed
    readonly property bool overflows: measure.implicitWidth > root.textWidth

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
        visible: !root.overflows
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
        visible: root.overflows
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

        NumberAnimation on x {
            running: root.overflows && root.visible
            loops: Animation.Infinite
            from: root.bleed
            to: root.bleed - (measure.implicitWidth + root.gap)
            duration: Math.max(1000, root.text.length * 360)
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
