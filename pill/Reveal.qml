import QtQuick
import qs.services

/**
 * One show/hide motion. A straight-line `phase` follows `on` over `duration`;
 * `value` is that phase through the ease-out curve. Hiding plays the same
 * motion backwards, so close is exactly open in reverse. Derive every size,
 * opacity and offset of the motion from `value`.
 */
QtObject {
    id: root

    property bool on: false
    property int duration: 180

    /** Straight-line progress 0..1. */
    property real phase: root.on ? 1 : 0
    Behavior on phase { NumberAnimation { duration: root.duration; easing.type: Easing.Linear } }

    /** Eased progress 0..1 to draw with. */
    readonly property real value: Theme.easeOut(root.phase)
}
