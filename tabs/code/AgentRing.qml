import QtQuick
import QtQuick.Shapes
import qs.services
import qs.common

/**
 * One agent usage ring: a track circle plus a value arc from 12 o'clock
 * clockwise (butt caps, no rounding). Like UsageRing, but leaves the center
 * mark to the caller (a BrandMark or an Icon) instead of baking one in, so
 * AgentsRings can also stack two of these to make the weekly double ring.
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

    default property alias content: centerSlot.data

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

            ColorFade on strokeColor { duration: Theme.stateMs }

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

    Item {
        id: centerSlot
        anchors.centerIn: parent
    }
}
