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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.listMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
            NumberAnimation { property: "x"; from: -12; to: 0; duration: Theme.listMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
        }
    }
    remove: Transition {
        enabled: root.animateChanges
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.hoverMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
            NumberAnimation { property: "x"; to: 12; duration: Theme.hoverMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
        }
    }
    displaced: Transition {
        enabled: root.animateChanges
        NumberAnimation { properties: "y"; duration: Theme.listMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.standardCurve }
    }
}
