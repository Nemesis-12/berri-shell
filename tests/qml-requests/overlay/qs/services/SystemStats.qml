pragma Singleton
import QtQuick

// Fake System tab numbers: the process table reads only these two.
QtObject {
    property var processes: []
    property int threadCount: 1
}
