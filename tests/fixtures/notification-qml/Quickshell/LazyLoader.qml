import QtQuick
// Keeps the D-Bus server component uncreated in the isolated QML test.
Item {
    property bool active: false
    default property Component component
}
