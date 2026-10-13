pragma Singleton
import QtQml

// Holds file contents and pending downloads without disk or network access.
QtObject {
    property var texts: ({})
    property bool failWrite: false
    /** Paths whose atomic writes fail. */
    property var deniedWrites: ({})
    property var downloads: []
    /** Paths whose reads fail with a permission error. */
    property var deniedReads: ({})
    /** Readers whose first result is held until the test releases it. */
    property var heldReads: ({})
    /** Watched readers receive file changes from tests. */
    property var readers: ({})
    /** Paths written by a FileView, in order. */
    property var writes: []
    /** What happened, in order: "write", "write-failed" and entries that a test adds. */
    property var events: []
    function note(event) { events = events.concat([event]); }
    function reset() { texts = ({}); failWrite = false; deniedWrites = ({}); downloads = []; deniedReads = ({}); heldReads = ({}); readers = ({}); writes = []; events = []; }
}
