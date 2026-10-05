pragma Singleton
import QtQml

// Holds file contents and pending downloads without disk or network access.
QtObject {
    property var texts: ({})
    property bool failWrite: false
    property var downloads: []
    /** Paths whose reads fail with a permission error. */
    property var deniedReads: ({})
    /** Paths written by a FileView, in order. */
    property var writes: []
    /** What happened, in order: "write", "write-failed" and entries that a test adds. */
    property var events: []
    function note(event) { events = events.concat([event]); }
    function reset() { texts = ({}); failWrite = false; downloads = []; deniedReads = ({}); writes = []; events = []; }
}
