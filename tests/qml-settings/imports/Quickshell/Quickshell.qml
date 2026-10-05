pragma Singleton
import QtQuick

// Gives fixed user and home names, so the test never reads the real account.
QtObject {
    function env(name) {
        return name === "USER" ? "tester" : name === "HOME" ? "/home/tester" : "";
    }
}
