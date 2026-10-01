import QtQuick
import qs.common
import qs.services

/**
 * One 28x28 media-transport button (prev/play-pause/next) for Media.qml.
 * `filled` gives the play/pause look (accent fill, no border); otherwise
 * it is an outlined button that lights up its border on hover.
 */
Rectangle {
    id: root

    property string icon: ""
    property bool filled: false
    property bool enabled: true

    signal activated

    implicitWidth: 28
    implicitHeight: 28
    radius: 3
    color: filled ? Theme.accent : "transparent"
    border.width: filled ? 0 : 1
    border.color: (!filled && mouse.containsMouse && root.enabled) ? Theme.accentLine : Theme.border
    opacity: root.enabled ? 1 : 0.4
    Fade on opacity { duration: Theme.stateMs }
    scale: (mouse.pressed && root.enabled) ? 0.94 : 1

    ColorFade on border.color {}
    Behavior on scale {
        NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: 12
        strokeWidth: 1.5
        color: root.filled ? Theme.onAccent : Theme.fg2
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
