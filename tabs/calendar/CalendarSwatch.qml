import QtQuick
import qs.services

/**
 * Sharp color square of the color pickers. `colorKey` is a preset key or
 * "#rrggbb". The chosen square gets a 1.5px outline in the text color, 2px
 * off the square (the gap shows `ringGap`, the color of what lies behind).
 * The ring fades in and out. With `interactive`, the square is a button that
 * brightens on hover; otherwise the parent handles the mouse.
 */
Item {
    id: root

    property string colorKey: "accent"
    property bool selected: false
    property color ringGap: Theme.raised
    property bool interactive: true
    property alias hovered: mouse.containsMouse

    signal clicked

    width: 12
    height: 12

    // Ring: outer outline in the text color, then the gap.
    Item {
        anchors.fill: parent
        opacity: root.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.stateMs; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3.5
            color: Theme.fg
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            color: root.ringGap
        }
    }

    Rectangle {
        anchors.fill: parent
        color: CalendarColors.resolve(root.colorKey)
    }

    // Hover: a light veil (the mock's brightness filter).
    Rectangle {
        anchors.fill: parent
        color: "white"
        opacity: root.interactive && mouse.containsMouse ? 0.14 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.hoverMs; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
