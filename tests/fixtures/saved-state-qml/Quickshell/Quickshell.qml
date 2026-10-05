pragma Singleton
import QtQml

// Fixed home folder and shell path, so the test never reads real user data.
QtObject {
    property var screens: []
    function env(name) { return name === "HOME" ? "/home/tester" : ""; }
    function shellPath(path) { return "/shell/" + path; }
}
