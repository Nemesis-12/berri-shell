import QtQuick
import qs.common
import qs.services

/**
 * One agent switch button of the code tab (mock 5C tab button): the agent's
 * mark and name at the bottom left, an accent bar on top when selected.
 */
Item {
    id: root

    property string brand: "claude"
    property string label: ""
    property bool selected: false
    signal clicked()

    readonly property bool hovered: button.hovered

    Rectangle {
        anchors.fill: parent
        color: root.selected ? Theme.oklabMix(Theme.card, Theme.accent, 82) : Theme.card
        ColorFade on color { duration: Theme.stateMs }
    }

    Rectangle {
        width: parent.width
        height: 2
        color: Theme.accentLight
        opacity: root.selected ? 1 : 0
        Fade on opacity { duration: Theme.stateMs }
    }

    BrandMark {
        x: 12
        y: 14
        brand: root.brand
        size: 14
        color: label.color
    }

    CondensedText {
        id: label
        x: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        text: root.label.toUpperCase()
        font.pixelSize: 16
        color: root.selected || root.hovered ? Theme.fg : Theme.dim
        ColorFade on color {}
    }

    // The brand and bottom label keep their mock positions above the button.
    HoverButton {
        id: button
        anchors.fill: parent
        hoverFill: "transparent"
        onClicked: root.clicked()
    }
}
