pragma Singleton
import QtQuick

// Stand-in for the weather service: only the values the views read.
QtObject {
    property string error: ""
    property real updatedAt: 0
    property bool ready: true
    property bool loading: false
    property string locationName: "Porto, PT"
    property int temperatureC: 24
    property string iconName: "cloud"
    property string conditionLabel: "Cloudy"
    readonly property var days: []
    function dayDetail(i) { return { tempC: 24, feelsLikeC: 25, maxC: 26, minC: 17, code: 3, isDay: true }; }
    function weatherGroup(code) { return "cloud"; }
    function iconForGroup(group, isDay) { return "cloud"; }
    function labelForGroup(group) { return "Cloudy"; }
    function refresh() {}
}
