import QtQuick
import qs.services
import qs.common

/**
 * Selectable tile of the media tab (output devices, shuffle, repeat). Lit
 * (`on`) it shows a soft accent fill, a 2px accent bar on top and accent
 * icon/sub colors; off it is a plain card that brightens its icon on hover.
 * Children go into the tile as content; they read the color properties.
 */
Item {
    id: root

    property bool on: false
    property bool available: true

    signal clicked

    readonly property bool hovered: mouse.containsMouse && root.available
    property color iconColor: on ? Theme.accentLight : (hovered ? Theme.fg : Theme.dim)
    property color labelColor: on ? Theme.fg : Theme.fg2
    property color subColor: on ? Theme.accentLight : Theme.dim

    default property alias content: holder.data

    opacity: available ? 1 : 0.4

    Fade on opacity { duration: Theme.stateMs }

    ColorFade on iconColor { duration: Theme.stateMs }
    ColorFade on labelColor { duration: Theme.stateMs }
    ColorFade on subColor { duration: Theme.stateMs }

    Rectangle {
        anchors.fill: parent
        color: root.on ? Qt.alpha(Theme.accentLight, 0.1) : Theme.card

        ColorFade on color { duration: Theme.stateMs }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.on ? 2 : 0
        color: Theme.accentLight

        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
    }

    Item {
        id: holder
        anchors.fill: parent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
