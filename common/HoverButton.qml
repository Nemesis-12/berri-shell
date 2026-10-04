import QtQuick
import qs.services

/**
 * Flat button with a mono label or an icon. On hover the fill and the
 * text color fade in and the cursor is a pointing hand. The fill is an overlay
 * that fades by opacity, so a transparent `fill` stays clean.
 * Set `sidePadding` (0 or more) to size the button from its content;
 * a negative value leaves the size to the caller.
 */
Rectangle {
    id: root

    property string label: ""
    property string icon: ""
    property real iconSize: 12
    property real iconStrokeWidth: 1.5
    property color fill: "transparent"
    property color hoverFill: Theme.hover
    property color textColor: Theme.fg2
    property color hoverTextColor: Theme.fg
    property real fontSize: 9
    property int weight: Font.Medium
    property real letterSpacing: 1.08
    property real sidePadding: -1
    /** Longest label width; a longer label is cut with "...". Negative: no limit. */
    property real maxTextWidth: -1

    readonly property bool hovered: area.containsMouse
    /** Width of the label alone, for a button sized to its text. */
    readonly property real implicitTextWidth: labelText.implicitWidth

    signal clicked

    readonly property color shownTextColor: root.hovered ? root.hoverTextColor : root.textColor

    color: root.fill
    implicitWidth: root.sidePadding >= 0 ? (root.label !== "" ? labelText.width : iconItem.width) + root.sidePadding * 2 : 0

    Rectangle {
        anchors.fill: parent
        color: root.hoverFill
        opacity: root.hovered ? 1 : 0
        Fade on opacity {}
    }

    Icon {
        id: iconItem
        anchors.centerIn: parent
        visible: root.icon !== ""
        name: root.icon
        size: root.iconSize
        strokeWidth: root.iconStrokeWidth
        color: root.shownTextColor
        ColorFade on color {}
    }

    Text {
        textFormat: Text.PlainText
        id: labelText
        anchors.centerIn: parent
        visible: root.label !== ""
        text: root.label
        width: root.maxTextWidth < 0 ? implicitWidth : Math.min(implicitWidth, root.maxTextWidth)
        elide: Text.ElideRight
        font.family: Theme.mono
        font.pixelSize: root.fontSize
        font.weight: root.weight
        font.letterSpacing: root.letterSpacing
        color: root.shownTextColor
        ColorFade on color {}
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
