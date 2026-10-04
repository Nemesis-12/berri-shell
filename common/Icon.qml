import QtQuick
import QtQuick.Shapes
import "Icons.js" as Icons
import "../logic/IconLookup.js" as IconLookup

/**
 * Draws one Lucide icon (see assets/icons/lucide/, generated into Icons.js
 * by tools/lucide-to-qml.py) as a stroked QML path using CurveRenderer for smooth edges.
 */
Item {
    id: root

    property string name: ""
    property real size: 24
    property real strokeWidth: 1.5
    property color color: "white"

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: IconLookup.pathFor(Icons.paths, root.name) }
        }
    }
}
