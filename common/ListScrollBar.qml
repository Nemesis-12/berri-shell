import QtQuick
import qs.services

/**
 * A thin scroll thumb for a ListView. It shows only when the list is taller
 * than its window. Place it over the list; it follows the list's scroll
 * position. By default it fades in only while the list moves.
 */
Rectangle {
    id: root

    /** The list this thumb follows. */
    required property Flickable view

    /** Extra condition for showing the thumb. */
    property bool available: true

    /** Width of the thumb. */
    property real thickness: 3

    /** True: the thumb shows only while the list moves. */
    property bool onlyWhileMoving: true

    /** Distance from the top of the thumb's parent to the top of the list. */
    property real viewTop: 0

    visible: available && view.contentHeight > view.height
    width: thickness
    radius: thickness / 2
    color: Theme.border
    opacity: !onlyWhileMoving || view.moving ? 1 : 0
    y: viewTop + view.visibleArea.yPosition * view.height
    height: view.visibleArea.heightRatio * view.height

    Fade on opacity { duration: Theme.stateMs }
}
