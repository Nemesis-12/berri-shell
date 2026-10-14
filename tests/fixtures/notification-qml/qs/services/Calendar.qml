pragma Singleton
import QtQuick

QtObject {
    property bool ready: false
    property bool saveErrorShown: false
    signal revisionChanged()
    signal saveFailed(string message)
    function allItems() { return []; }
    function snooze(key, occurrenceDate, minutes) {}
    function setDone(key, done, occurrenceDate) {}
}
