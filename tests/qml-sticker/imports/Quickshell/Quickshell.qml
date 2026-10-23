pragma Singleton
import QtQuick

// Gives a fixed home folder and a fixed shell folder, so the test never reads the real account.
QtObject {
    function env(name) {
        return name === "HOME" ? "/home/tester" : "";
    }
    function shellPath(relative) {
        return "/shell/" + relative;
    }
}
