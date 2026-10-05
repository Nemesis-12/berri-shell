import QtQuick
import QtQuick.Shapes
import qs.services

/** A track circle and a value arc from 12 o'clock clockwise. */
Item {
    id: root

    property real size: 40
    property real radius: 17
    property real strokeWidth: 3
    property color trackColor: Theme.border
    property color valueColor: Theme.accent
    /** 0-100. */
    property real value: 0
    property bool fadeValueColor: false

    readonly property real degreesPerPercent: 3.6
    readonly property real animateAboveDegrees: 36
    property bool arcReady: false

    // Skip animation for small samples to avoid frame-by-frame redraws; animate large visible changes.
    function updateArc() {
        const nextAngle = value * degreesPerPercent;
        const largeChange = Math.abs(nextAngle - valueArc.sweepAngle) >= animateAboveDegrees;
        arcAnimation.stop();
        arcBehavior.enabled = visible && largeChange;
        valueArc.sweepAngle = nextAngle;
    }

    onValueChanged: if (arcReady) updateArc()
    onVisibleChanged: {
        if (!arcReady || visible) return;
        arcAnimation.stop();
        arcBehavior.enabled = false;
        valueArc.sweepAngle = value * degreesPerPercent;
    }
    Component.onCompleted: {
        arcBehavior.enabled = false;
        valueArc.sweepAngle = value * degreesPerPercent;
        arcReady = true;
    }

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

            ColorFade on strokeColor {
                enabled: root.fadeValueColor
                duration: Theme.stateMs
            }

            PathAngleArc {
                id: valueArc
                centerX: root.size / 2
                centerY: root.size / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: -90
                sweepAngle: 0

                Behavior on sweepAngle {
                    id: arcBehavior
                    enabled: false
                    StandardMotion {
                        id: arcAnimation
                        duration: Theme.stateMs
                    }
                }
            }
        }
    }
}
