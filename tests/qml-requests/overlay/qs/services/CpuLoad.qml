pragma Singleton
import QtQuick

// Fake CPU load: the Home ring reads only these two.
QtObject {
    property real percent: 0
    property bool ready: false
}
