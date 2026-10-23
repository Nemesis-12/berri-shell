pragma Singleton
import QtQuick

// Fake battery states.
QtObject {
    enum Kind { Unknown, Charging, Discharging, FullyCharged }
}
