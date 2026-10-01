import QtQuick

/**
 * Put this inside a view. While the view is on screen, it counts as one
 * viewer of `service`. A service starts its timers when its `viewers` goes
 * above 0 and stops them when it returns to 0. This is the one rule for
 * "run only while someone looks": a hidden tab, or a closed panel, is not
 * visible, so it is not isWatching.
 */
Item {
    id: root

    /** A singleton with an int property `viewers`. */
    property var service: null

    property bool isWatching: false

    function refreshWatching() {
        if (!root.service) return;
        if (root.visible && !root.isWatching) {
            root.service.viewers += 1;
            root.isWatching = true;
        } else if (!root.visible && root.isWatching) {
            root.service.viewers -= 1;
            root.isWatching = false;
        }
    }

    onVisibleChanged: refreshWatching()
    Component.onCompleted: refreshWatching()
    Component.onDestruction: {
        if (root.isWatching) root.service.viewers -= 1;
    }
}
