pragma Singleton
import QtQuick

// Fixed theme tokens for the hidden-view checks. It never reads the saved theme.
Item {
    property color shell: "#101010"
    property color sunk: "#0c0c0c"
    property color raised: "#262626"
    property color card: "#191919"
    property color accent: "#849966"
    property color accentLight: "#b2cc88"
    property color accentSecondary: "#88aacc"
    property color accentLine: "#72885c"
    property color accentFill: "#2a3320"
    property color fg: "#ffffff"
    property color fg2: "#dddddd"
    property color dim: "#aaaaaa"
    property color border: "#333333"
    property color onAccentValue: "#111111"
    readonly property color onAccent: onAccentValue
    property string mono: "IBM Plex Mono"
    property string condensed: "IBM Plex Sans Condensed"
    property int stateMs: 300
    property int hoverMs: 180
    property var standardCurve: [0.4, 0, 0.2, 1, 1, 1]
    function oklabMix(from, to, percent) { return from; }
}
