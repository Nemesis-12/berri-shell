import QtQuick
import qs.services

/**
 * Hover tooltip bubble, shared by the battery power-mode buttons and the
 * system usage rings. Instantiate as a child of the hoverable item, bind
 * `hovered` to that item's HoverHandler, and set `overlayItem` to a top-level
 * item (e.g. the dashboard) so the bubble draws above the Home grid
 * instead of being clipped by a cell's `clip: true`. Positions itself
 * centered above `anchorItem` with a 6px gap, flipping below if that
 * would put it outside `boundsItem` (defaults to `overlayItem`).
 *
 * The anchor position is read on every frame while the bubble is hovered or
 * visible, so it follows a moving anchor or a sliding panel.
 */
Item {
    id: root

    required property Item anchorItem
    required property Item overlayItem
    property Item boundsItem: overlayItem
    property string text: ""
    property bool hovered: false

    readonly property int gap: 6
    property real shownOpacity: 0

    // Where the anchor sits inside the overlay. Re-read every frame, but only
    // while the bubble is hovered or fading, so moving parents (the panel
    // slide) carry the bubble without extra bindings on every transform.
    property point anchorPosition: Qt.point(0, 0)

    /** Reads the anchor position in overlay coordinates. */
    function followAnchor() {
        if (!root.anchorItem || !root.overlayItem) return;
        var place = root.anchorItem.mapToItem(root.overlayItem, 0, 0);
        if (place.x !== root.anchorPosition.x || place.y !== root.anchorPosition.y)
            root.anchorPosition = place;
    }

    FrameAnimation {
        running: root.hovered || bubble.visible
        onTriggered: root.followAnchor()
    }

    readonly property real bubbleX: root.anchorItem && root.boundsItem
        ? Math.max(0, Math.min(root.boundsItem.width - bubble.width,
            root.anchorPosition.x + root.anchorItem.width / 2 - bubble.width / 2)) : 0
    readonly property real bubbleY: root.anchorItem
        ? (root.anchorPosition.y - root.gap - bubble.height >= 0
            ? root.anchorPosition.y - root.gap - bubble.height
            : root.anchorPosition.y + root.anchorItem.height + root.gap) : 0

    Timer {
        id: showTimer
        interval: 400
        onTriggered: root.shownOpacity = 1
    }

    onHoveredChanged: {
        if (hovered) {
            root.followAnchor();
            showTimer.restart();
        } else {
            showTimer.stop();
            root.shownOpacity = 0;
        }
    }

    Rectangle {
        id: bubble
        parent: root.overlayItem
        visible: opacity > 0.001
        opacity: root.shownOpacity
        color: Theme.raised
        border.width: 1
        border.color: Theme.border
        radius: 3
        width: label.implicitWidth + 16
        height: label.implicitHeight + 10
        x: root.bubbleX
        y: root.bubbleY

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.standardCurve
            }
        }

        Text {
            textFormat: Text.PlainText
            id: label
            anchors.centerIn: parent
            text: root.text
            font.family: Theme.mono
            font.weight: Font.Medium
            font.pixelSize: 10
            font.letterSpacing: 10 * 0.08
            color: Theme.fg2
        }
    }
}
