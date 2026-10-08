import QtQuick

/**
 * Color animation on the mock's standard curve, cubic-bezier(.4, 0, .2, 1).
 * Set `duration` and the property to move, as for a ColorAnimation. The curve
 * lives here only.
 */
ColorAnimation {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.standardCurve
}
