import QtQuick
import qs.services

/**
 * Number animation on the spring-like curve of the pill and panel morphs, cubic-bezier(.32, .72, 0, 1).
 * Set `duration` and the property to move, as for a NumberAnimation. The
 * curve lives here only.
 */
NumberAnimation {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.springCurve
}
