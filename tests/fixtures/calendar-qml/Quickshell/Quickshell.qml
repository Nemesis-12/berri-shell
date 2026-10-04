pragma Singleton
import QtQml

// Keeps paths and process calls inside the test copy.
QtObject {
    function env(name) { return name === "HOME" ? "/calendar-test" : ""; }
    function shellPath(path) { return Qt.resolvedUrl(path).toString(); }
    /** Commands that calendar code asked to run detached. */
    property var detached: []
    function execDetached(command) { detached = detached.concat([command]); }
}
