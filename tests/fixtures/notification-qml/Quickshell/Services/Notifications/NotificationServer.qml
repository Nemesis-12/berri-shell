import QtQuick
// Matches the server's settings without registering a D-Bus name.
QtObject {
    property bool actionsSupported
    property bool bodySupported
    property bool bodyMarkupSupported
    property bool imageSupported
    property bool persistenceSupported
    signal notification(var n)
}
