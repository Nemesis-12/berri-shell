import QtQuick
import qs.common
import qs.services

/** 26x26 icon button on an alert row (mark read, snooze, dismiss). */
HoverButton {
    id: root

    property bool shown: true

    width: 26
    height: 26
    iconSize: 13
    iconStrokeWidth: 1.8
    textColor: Theme.dim
    opacity: shown ? 1 : 0
    enabled: shown

    Fade on opacity { duration: Theme.stateMs }
}
