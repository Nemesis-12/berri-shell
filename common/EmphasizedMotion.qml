import QtQuick
import qs.services

/**
 * Number animation with a fast start and a long soft stop, cubic-bezier(.2, 0, 0, 1).
 * Set `duration` and the property to move, as for a NumberAnimation. The
 * curve lives here only.
 */
NumberAnimation {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.emphasizedCurve
}
