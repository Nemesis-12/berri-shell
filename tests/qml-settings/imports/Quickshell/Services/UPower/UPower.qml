pragma Singleton
import QtQuick

// Fake power source: on AC, with no battery until a test sets `displayDevice`.
QtObject {
    property bool onBattery: false
    property var displayDevice: null
}
