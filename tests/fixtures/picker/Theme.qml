pragma Singleton
import QtQuick
QtObject {
 property string currentKey: "test"
 property var current: null
 property var palettes: []
 property string dashboardStyle: "spine"
 property bool transitioning: false
 property var fromRaw: ({})
 property var toRaw: ({})
 property int hoverMs: 180
 property int stateMs: 300
 property int transitionDurationMs: 450
 property var springCurve: [0.32, 0.72, 0, 1, 1, 1]
 property var standardCurve: [0.4, 0, 0.2, 1, 1, 1]
 property string mono: "sans-serif"
 property string condensed: "sans-serif"
 readonly property color onAccent: Qt.rgba(1,1,1,1)
 signal wallpaperTransition(string mode, int durationMs)
 property color accent: "#888888"
 property color accentLight: "#888888"
 property color border: "#888888"
 property color card: "#888888"
 property color dim: "#888888"
 property color fg: "#888888"
 property color raised: "#888888"
 property color selection: "#888888"
 property color shell: "#888888"
 property color darkerBackground: "#888888"
 property color accentFill: "#888888"
 property color hover: "#888888"
 property color fg2: "#888888"
}