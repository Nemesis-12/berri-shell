import QtQuick
import qs.common
import qs.services

/**
 * One toggle-grid tile (ticket 15-18): an icon top-left, a mono label and a
 * condensed sub-line bottom-left, and an on/off style that animates. An
 * optional small chevron button top-right (Wi-Fi/Bluetooth) opens a picker;
 * clicking the tile body itself calls onToggled.
 */
Rectangle {
    id: root

    property string iconName: ""
    property string label: ""
    property string sub: ""
    property bool on: false
    property bool showChevron: false

    signal toggled
    signal chevronClicked

    readonly property color bgColor: on ? Theme.accentFill : Theme.raised
    readonly property color borderColor: on ? Theme.accentLine : Theme.border
    readonly property color iconColor: on ? Theme.accentLight : Theme.dim
    readonly property color labelColor: on ? Theme.fg : Theme.fg2
    readonly property color subColor: on ? Theme.accentLight : Theme.dim

    radius: 4
    border.width: 1
    border.color: borderColor
    color: bgColor
    scale: tileMouse.pressed ? 0.97 : 1

    ColorFade on color { duration: Theme.stateMs }
    ColorFade on border.color { duration: Theme.stateMs }
    Behavior on scale {
        NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 9
        spacing: 0

        Icon {
            name: root.iconName
            size: 18
            strokeWidth: 1.5
            color: root.iconColor

            ColorFade on color { duration: Theme.stateMs }
        }

        Item { width: 1; height: parent.height - 18 - labelCol.height }

        Column {
            id: labelCol
            spacing: 4

            Text {
                text: root.label
                font.family: Theme.mono
                font.weight: Font.Medium
                font.pixelSize: 10
                font.letterSpacing: 1.0
                color: root.labelColor

                ColorFade on color { duration: Theme.stateMs }
            }

            Text {
                width: Math.min(implicitWidth, root.width - 18)
                text: root.sub
                font.family: Theme.condensed
                font.weight: Font.Medium
                font.pixelSize: 11
                color: root.subColor
                elide: Text.ElideRight
                maximumLineCount: 1

                ColorFade on color { duration: Theme.stateMs }
            }
        }
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    Rectangle {
        id: chevron
        visible: root.showChevron
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5
        width: 22
        height: 22
        radius: 3
        border.width: 1
        border.color: chevronMouse.containsMouse ? Theme.accentLine : Theme.border
        color: Theme.shell

        ColorFade on border.color {}

        Icon {
            anchors.centerIn: parent
            name: "chevron-right"
            size: 12
            strokeWidth: 2
            color: chevronMouse.containsMouse ? Theme.accentLight : Theme.fg2

            ColorFade on color {}
        }

        MouseArea {
            id: chevronMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => { root.chevronClicked(); mouse.accepted = true; }
        }
    }
}
