pragma Singleton
import QtQuick

// Small stand-in with the tokens the weather parts read.
QtObject {
    readonly property color fg: "#ffffff"
    readonly property color fg2: "#d6d4dc"
    readonly property color dim: "#a4a4b0"
    readonly property color raised: "#241e2e"
    readonly property color accentLight: "#ff8800"
    readonly property int stateMs: 300
    readonly property int hoverMs: 180
    readonly property string mono: "monospace"
    readonly property string condensed: "sans"
    readonly property var standardCurve: [0.4, 0, 0.2, 1, 1, 1]
    readonly property var emphasizedCurve: [0.4, 0, 0.2, 1, 1, 1]
}
