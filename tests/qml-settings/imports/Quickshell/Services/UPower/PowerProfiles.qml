pragma Singleton
import QtQuick

// Fake system power profile. It starts as Balanced, like the real one.
QtObject {
    property int profile: PowerProfile.Balanced
    property bool hasPerformanceProfile: true
}
