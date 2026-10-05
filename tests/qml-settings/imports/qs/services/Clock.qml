pragma Singleton
import QtQuick

// Fake clock: the test emits minuteChanged() to move time forward.
QtObject {
    property int viewers: 0
    signal minuteChanged()
}
