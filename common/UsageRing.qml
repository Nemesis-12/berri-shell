import QtQuick
import QtQuick.Shapes
import qs.services

/**
 * One usage ring: a track circle, a value arc from 12 o'clock clockwise
 * (butt caps, no rounding), and a centered Lucide icon. Used by SystemRings
 * for CPU/RAM/disk. The arc animates to a new value instead of jumping.
 */
Item {
    id: root

    property real size: 40
    property real radius: 17
    property real strokeWidth: 3
    property color trackColor: Theme.border
    property color valueColor: Theme.accent
    /** 0-100. */
    property real value: 0

    property string iconName: ""
    property real iconSize: 15
    property real iconStrokeWidth: 1.5
    property color iconColor: Theme.fg

    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            strokeColor: root.valueColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: -90
                sweepAngle: root.value * 3.6

                Behavior on sweepAngle {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.standardCurve
                    }
                }
            }
        }
    }

    Icon {
        anchors.centerIn: parent
        name: root.iconName
        size: root.iconSize
        strokeWidth: root.iconStrokeWidth
        color: root.iconColor
    }
}
