import QtQuick
import QtQuick.Effects
import qs.services

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
    property int hoverMs: Theme.hoverMs

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
    // Written only by their own binding and Behavior (QML cannot animate readonly).
    property real hoverBlendOffset: hovered ? hoverOffset : restOffset
    property real hoverBlendStrength: hovered ? hoverStrength : restStrength
    property real hoverBlendBlur: hovered ? hoverBlur : restBlur
    Behavior on hoverBlendOffset { NumberAnimation { duration: root.hoverMs; easing.type: Easing.OutCubic } }
    Behavior on hoverBlendStrength { NumberAnimation { duration: root.hoverMs; easing.type: Easing.OutCubic } }
    Behavior on hoverBlendBlur { NumberAnimation { duration: root.hoverMs; easing.type: Easing.OutCubic } }

    // The value `openProgress` of the way from `from` to `to`.
    function towardOpen(from: real, to: real): real {
        return from + (to - from) * openProgress
    }

    anchors.fill: target

    RectangularShadow {
        anchors.fill: parent
        radius: root.target.radius
        color: Qt.rgba(0, 0, 0, root.towardOpen(root.hoverBlendStrength, root.openStrength))
        blur: root.towardOpen(root.hoverBlendBlur, root.openBlur)
        offset: Qt.vector2d(0, root.towardOpen(root.hoverBlendOffset, root.openOffset))
    }
}
