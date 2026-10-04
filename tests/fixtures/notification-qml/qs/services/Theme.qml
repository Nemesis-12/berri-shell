pragma Singleton
import QtQuick
// Fixed test colors avoid loading desktop settings or starting theme processes.
QtObject {
    property color fg: "white"
    property color fg2: "white"
    property color dim: "gray"
    property color card: "black"
    property color shell: "black"
    property color border: "gray"
    property color hover: "gray"
    property color raised: "black"
    property color sunk: "black"
    property color selectionSoft: "black"
    property color accentLight: "white"
    property color accentFill: "black"
    property color onAccent: "black"
    property string mono: "monospace"
    property string condensed: "sans-serif"
    property int hoverMs: 180
    property int stateMs: 300
    property int listMs: 300
    property var springCurve: [0.2, 0, 0.2, 1, 1, 1]
    property var standardCurve: [0.2, 0, 0.2, 1, 1, 1]
    property var emphasizedCurve: [0.2, 0, 0.2, 1, 1, 1]
}
