import QtQuick
import qs.services

/**
 * Number animation on the mock's standard curve, cubic-bezier(.4, 0, .2, 1).
 * Set `duration` and the property to move, as for a NumberAnimation. The
 * curve lives here only.
 */
NumberAnimation {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.standardCurve
}
