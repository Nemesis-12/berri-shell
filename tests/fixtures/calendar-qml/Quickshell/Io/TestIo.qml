pragma Singleton
import QtQml

// Holds file contents and pending downloads without disk or network access.
QtObject {
    property var texts: ({})
    property bool failWrite: false
    property var downloads: []
    function reset() { texts = ({}); failWrite = false; downloads = []; }
}
