import QtQuick
import qs.services

/**
 * Hex color box of the color pickers: live swatch, "#", and a text field for
 * the digits. `colorKey` is the current color (preset key or "#rrggbb"). A
 * valid hex (3 or 6 digits) is sent with `picked` while typing; an invalid
 * text turns the border red and goes back to the current color on blur.
 */
Rectangle {
    id: root

    property string colorKey: "accent"
    readonly property alias input: hexInput
    readonly property bool invalid: hexInput.text.trim() !== "" && CalendarColors.normHex(hexInput.text) === ""

    /** A valid hex was typed. Carries "#rrggbb". */
    signal picked(string hex)

    /** Esc pressed in the field. */
    signal escaped

    height: 28
    color: Theme.shell
    border.width: 1
    border.color: root.invalid ? CalendarColors.paletteColor("red", Theme.accent) : Theme.border

    Behavior on border.color {
        ColorAnimation { duration: Theme.stateMs; easing.type: Easing.OutCubic }
    }

    // Shows the current color's digits, except while the typed text is what set the color.
    property bool typing: false
    onColorKeyChanged: if (!root.typing) hexInput.text = CalendarColors.hexDigits(root.colorKey)
    Component.onCompleted: hexInput.text = CalendarColors.hexDigits(root.colorKey)

    Rectangle {
        id: dot
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        color: CalendarColors.resolve(root.colorKey)

        Behavior on color {
            ColorAnimation { duration: Theme.stateMs; easing.type: Easing.OutCubic }
        }
    }

    Text {
        id: hash
        anchors.left: dot.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: "#"
        font.family: Theme.mono
        font.pixelSize: 11
        font.weight: Font.Medium
        color: Theme.mute
    }

    TextInput {
        id: hexInput
        anchors.left: hash.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        maximumLength: 7
        activeFocusOnTab: true
        font.family: Theme.mono
        font.pixelSize: 11
        font.weight: Font.Medium
        font.letterSpacing: 0.66
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        cursorDelegate: Rectangle { width: 1; color: Theme.accentLight }

        Text {
            visible: hexInput.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: "hex"
            font: hexInput.font
            color: Theme.mute
        }

        onTextEdited: {
            var hex = CalendarColors.normHex(text);
            if (hex === "") return;
            root.typing = true;
            root.picked(hex);
            root.typing = false;
        }
        onActiveFocusChanged: if (!activeFocus) text = CalendarColors.hexDigits(root.colorKey)
        Keys.onEscapePressed: root.escaped()
    }
}
