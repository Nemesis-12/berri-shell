import QtQuick
import qs.services

/**
 * ListView whose rows fade and slide in and out and slide closed when the
 * rows change (use ShownRows.js to keep the rows in step). Set
 * `animateChanges: false` while the list is reset on purpose, for example
 * when the day changes.
 */
ListView {
    id: root

    property bool animateChanges: true

    clip: true
    boundsBehavior: Flickable.StopAtBounds

    add: Transition {
        enabled: root.animateChanges
        ParallelAnimation {
            StandardMotion { property: "opacity"; from: 0; to: 1; duration: Theme.listMs }
            StandardMotion { property: "x"; from: -12; to: 0; duration: Theme.listMs }
        }
    }
    remove: Transition {
        enabled: root.animateChanges
        ParallelAnimation {
            StandardMotion { property: "opacity"; to: 0; duration: Theme.hoverMs }
            StandardMotion { property: "x"; to: 12; duration: Theme.hoverMs }
        }
    }
    displaced: Transition {
        enabled: root.animateChanges
        StandardMotion { properties: "y"; duration: Theme.listMs }
    }
}
