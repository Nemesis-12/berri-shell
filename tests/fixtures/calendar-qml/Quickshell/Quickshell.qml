pragma Singleton
import QtQml

// Keeps paths and process calls inside the test copy.
QtObject {
    function env(name) { return name === "HOME" ? "/calendar-test" : ""; }
    function shellPath(path) { return Qt.resolvedUrl(path).toString(); }
    function execDetached(command) { throw new Error("Unexpected detached process: " + command); }
}
