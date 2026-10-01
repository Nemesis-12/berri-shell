import QtQuick
import QtQuick.Shapes
import "../logic/BrandPaths.js" as BrandPaths
import qs.tabs.code

/**
 * The Claude spark or the Codex mark, drawn as a filled shape in a flat
 * theme color (not brand colors). Path data is copied from assets/brands/
 * (see its README) into BrandPaths.js. Used as the center mark of an
 * AgentRing.
 */
Item {
    id: root

    property string brand: "claude" // "claude" | "codex"
    property real size: 15
    property color color: "white"

    readonly property real viewBoxSize: brand === "claude" ? 256 : 24

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: root.viewBoxSize
        height: root.viewBoxSize
        scale: root.size / root.viewBoxSize
        transformOrigin: Item.TopLeft
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            // The Codex mark has a cut-out arrow; its source SVG uses fill-rule
            // evenodd. The Claude spark's disjoint blobs render fine either way.
            fillRule: root.brand === "codex" ? ShapePath.OddEvenFill : ShapePath.WindingFill
            PathSvg { path: root.brand === "claude" ? BrandPaths.claude : BrandPaths.codex }
        }
    }
}
