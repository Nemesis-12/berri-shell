import QtQuick

/**
 * Put this inside a view. While the view is on screen (and `when` is true),
 * it counts as one owner of `service[counter]`. A service starts its work
 * when the count goes above 0 and stops it when the count returns to 0. This
 * is the one rule for "run only while someone looks": a hidden tab, or a
 * closed panel, is not visible, so it releases its count. Two monitors each
 * add one, so the work continues until the last view releases.
 *
 * Default use: `WhileVisible { service: Clock }` counts in `viewers`.
 * Other shared requests use `counter` and `when`, for example
 * `WhileVisible { service: MediaPlayer; counter: "seekers"; when: scrub.pressed }`.
 */
Item {
    id: root

    /** A singleton with an int property named `counter`. */
    property var service: null

    /** Name of the int property on `service` that this item counts in. */
    property string counter: "viewers"

    /** Extra condition. The item counts only while it is visible and this is true. */
    property bool when: true

    property bool isWatching: false

    function refreshWatching() {
        if (!root.service) return;
        var wanted = root.visible && root.when;
        if (wanted && !root.isWatching) {
            root.service[root.counter] += 1;
            root.isWatching = true;
        } else if (!wanted && root.isWatching) {
            root.service[root.counter] -= 1;
            root.isWatching = false;
        }
    }

    onVisibleChanged: refreshWatching()
    onWhenChanged: refreshWatching()
    Component.onCompleted: refreshWatching()
    Component.onDestruction: {
        if (root.isWatching) root.service[root.counter] -= 1;
    }
}
