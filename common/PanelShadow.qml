import QtQuick
import QtQuick.Effects

/**
 * The soft shadow under a panel. It reads only the size and radius of
 * `target`, never its content, so a change inside the panel does not redraw
 * the shadow. The look has three states (rest, pointer over, open); `hovered`
 * fades between the first two over `hoverMs`, `openProgress` (0..1) moves on
 * to the open look. Offset and blur are in pixels, strength is 0..1.
 */
Item {
    id: root

    /** The panel that casts the shadow. */
    required property Rectangle target
    property bool hovered: false
    property real openProgress: 0
    property int hoverMs: 400

    property real restOffset: 0
    property real restStrength: 0
    property real restBlur: 0

    property real hoverOffset: restOffset
    property real hoverStrength: restStrength
    property real hoverBlur: restBlur

    property real openOffset: restOffset
    property real openStrength: restStrength
    property real openBlur: restBlur

    // The rest look, moved to the hover look when the pointer is over.
    property real offsetNow: hovered ? hoverOffset : restOffset
    property real strengthNow: hovered ? hoverStrength : restStrength
    property real blurNow: hovered ? hoverBlur : restBlur
    Behavior on offsetNow { NumberAnimation { duration: root.hoverMs } }
    Behavior on strengthNow { NumberAnimation { duration: root.hoverMs } }
    Behavior on blurNow { NumberAnimation { duration: root.hoverMs } }

    anchors.fill: target

    RectangularShadow {
        anchors.fill: parent
        radius: root.target.radius
        color: Qt.rgba(0, 0, 0, root.strengthNow + (root.openStrength - root.strengthNow) * root.openProgress)
        blur: root.blurNow + (root.openBlur - root.blurNow) * root.openProgress
        offset: Qt.vector2d(0, root.offsetNow + (root.openOffset - root.offsetNow) * root.openProgress)
    }
}
