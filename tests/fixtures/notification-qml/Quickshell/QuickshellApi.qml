pragma Singleton
import QtQuick
// Test replacement for the icon theme lookup: no theme icon exists.
QtObject {
    function iconPath(name, check) { return ""; }
}
