import QtQuick
import qs.services

/**
 * Mono or condensed text that fades out, swaps to its new `value` and fades
 * back in when `value` changes. The first value shows at once.
 */
Text {
    textFormat: Text.PlainText
    id: root

    property string value: ""

    color: Theme.fg
    font.family: Theme.condensed
    font.weight: Font.Medium

    onValueChanged: {
        if (text === "") text = value;
        else swap.restart();
    }
    Component.onCompleted: text = value

    SequentialAnimation {
        id: swap
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InQuad }
        ScriptAction { script: root.text = root.value }
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 170; easing.type: Easing.OutQuad }
    }
}
