import QtQuick
// Avoids icon-theme and image-provider calls in the isolated QML engine.
Item {
    property string appName
    property string appIcon
    property real size
    property real strokeWidth
    property color color
}
