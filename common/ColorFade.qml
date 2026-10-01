import QtQuick
import qs.services

/**
 * Fades a color property when it changes. Use as `ColorFade on color {}`.
 * Default is the hover fade; set `duration: Theme.stateMs` for selection and
 * state changes.
 */
Behavior {
    id: root

    property int duration: Theme.hoverMs

    ColorAnimation {
        duration: root.duration
        easing.type: Easing.OutCubic
    }
}
