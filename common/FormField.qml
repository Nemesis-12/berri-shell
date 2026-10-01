import QtQuick
import qs.services

// Date or time box. Invalid text returns to the saved value on blur.
Column {
    id: field

    property string label: ""
    property string value: ""
    property bool allowEmpty: false
    // Function: is this text a full valid value?
    property var validate: null
    readonly property bool textEntryActive: fieldInput.activeFocus
    signal typed(string v)
    signal stepped(int dir)
    signal escaped

    // Gives up the input cursor when the form or panel closes.
    function releaseFocus() {
        fieldInput.focus = false;
    }

    spacing: 5

    // Shows the value unless the user is typing a valid text right now.
    onValueChanged: if (fieldInput.text !== field.value && !fieldInput.typing) fieldInput.text = field.value
    Component.onCompleted: fieldInput.text = field.value

    MonoText {
        height: 9
        verticalAlignment: Text.AlignVCenter
        text: field.label
        font.family: Theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 1.26
        color: Theme.dim
    }

    Rectangle {
        width: parent.width
        height: 30
        color: Theme.shell
        border.width: 1
        border.color: fieldInput.activeFocus ? Theme.accent : Theme.border

        ColorFade on border.color {}

        TextInput {
            id: fieldInput

            property bool typing: false

            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            activeFocusOnTab: true
            inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.Medium
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            cursorDelegate: Rectangle { width: 1; color: Theme.accentLight }

            onTextEdited: {
                var ok = field.validate(text) || (field.allowEmpty && text === "");
                if (!ok) return;
                typing = true;
                field.typed(text);
                typing = false;
            }
            onActiveFocusChanged: if (!activeFocus) text = field.value
            Keys.onUpPressed: { field.stepped(1); text = field.value; }
            Keys.onDownPressed: { field.stepped(-1); text = field.value; }
            Keys.onEscapePressed: field.escaped()
        }
    }
}
