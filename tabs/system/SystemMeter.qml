import QtQuick
import qs.services

/**
 * A flat horizontal meter: track plus fill. `value` is 0 to 1; the fill
 * slides to a new value instead of jumping. A change under one pixel is
 * ignored, so a live reading that only jitters does not keep the panel
 * animating (each animated frame costs a full repaint of the panel).
 */
Rectangle {
    id: root

    property real value: 0
    property color fillColor: Theme.accentLight

    color: Theme.border

    property real shown: 0

    onValueChanged: {
        var target = Math.max(0, Math.min(1, value));
        if (Math.abs(target - shown) * width >= 1 || target === 0 || target === 1) shown = target;
    }

    Rectangle {
        height: parent.height
        width: root.shown * parent.width
        color: root.fillColor

        Behavior on width {
            NumberAnimation {
                duration: 300
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.standardCurve
            }
        }
    }
}
