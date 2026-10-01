import QtQuick
import qs.services

/** One system usage ring with a centered Lucide icon. */
ArcRing {
    id: root

    property string iconName: ""
    property real iconSize: 15
    property real iconStrokeWidth: 1.5
    property color iconColor: Theme.fg

    Icon {
        anchors.centerIn: parent
        name: root.iconName
        size: root.iconSize
        strokeWidth: root.iconStrokeWidth
        color: root.iconColor
    }
}
