import QtQuick
import qs.services

/**
 * Text that slides and fades to its new value when `text` changes: the old
 * value moves up and out, the new one rises in. One progress value drives both.
 */
Item {
    id: root

    property string text: ""
    property font font
    property color color: Theme.fg
    property real lineHeight: 0
    property int elideMode: Text.ElideNone

    /** Distance in pixels the text travels. */
    property real travel: 6

    property string shown: text
    property string previous: text
    property real progress: 1

    implicitWidth: current.implicitWidth
    implicitHeight: current.implicitHeight

    onTextChanged: {
        if (root.text === root.shown) return;
        root.previous = root.shown;
        root.shown = root.text;
        slide.restart();
    }

    NumberAnimation {
        id: slide
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 260
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.standardCurve
    }

    Text {
        id: outgoing
        text: root.previous
        font: root.font
        color: root.color
        lineHeight: root.lineHeight > 0 ? root.lineHeight : 1
        lineHeightMode: root.lineHeight > 0 ? Text.FixedHeight : Text.ProportionalHeight
        y: -root.travel * root.progress
        opacity: 1 - root.progress
        visible: root.progress < 1
    }

    Text {
        id: current
        text: root.shown
        font: root.font
        color: root.color
        lineHeight: root.lineHeight > 0 ? root.lineHeight : 1
        lineHeightMode: root.lineHeight > 0 ? Text.FixedHeight : Text.ProportionalHeight
        y: root.travel * (1 - root.progress)
        opacity: root.progress
    }
}
