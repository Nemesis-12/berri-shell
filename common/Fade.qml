import QtQuick
import qs.services

/**
 * Fades a number property (opacity, scale, x) when it changes. Use as
 * `Fade on opacity {}`. Default is the hover fade; set
 * `duration: Theme.stateMs` for selection and state changes.
 */
Behavior {
    id: root

    property int duration: Theme.hoverMs

    NumberAnimation {
        duration: root.duration
        easing.type: Easing.OutCubic
    }
}
