import QtQuick
import qs.services

/**
 * An on/off switch: a track and a knob that slides. It draws the state and
 * sends `toggled` when clicked. The owner changes `checked`. Set
 * `interactive: false` when a larger area takes the click.
 */
Rectangle {
    id: root

    property bool checked: false
    property bool interactive: true

    property real knobSize: 14
    property real knobRadius: 1
    property color onColor: Theme.accent
    property color offColor: Theme.border

    /** Knob slide: the standard curve, or the emphasized curve when true. */
    property bool emphasized: false
    property int slideMs: 450

    signal toggled

    width: 34
    height: 18
    radius: 2
    color: checked ? onColor : offColor

    ColorFade on color { duration: Theme.stateMs }

    readonly property real inset: (height - knobSize) / 2
    readonly property real knobTarget: checked ? width - knobSize - inset : inset
    property bool ready: false

    // The knob slides on a change after the first layout; at first it sits at its place.
    onKnobTargetChanged: {
        if (!ready) { knob.x = knobTarget; return; }
        var slide = emphasized ? emphasizedSlide : standardSlide;
        slide.to = knobTarget;
        slide.restart();
    }
    Component.onCompleted: { knob.x = knobTarget; ready = true; }

    StandardMotion { id: standardSlide; target: knob; property: "x"; duration: root.slideMs }
    EmphasizedMotion { id: emphasizedSlide; target: knob; property: "x"; duration: root.slideMs }

    Rectangle {
        id: knob
        width: root.knobSize
        height: root.knobSize
        radius: root.knobRadius
        y: root.inset
        color: Theme.fg
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
