import QtQuick
import qs.common
import qs.services

// Fits the title to the available space and keeps the caret in view.
Item {
    id: root

    property bool readOnly: false
    property real availableHeight: 0
    readonly property bool textEntryActive: titleInput.activeFocus
    signal edited(string text)
    signal accepted
    signal escaped
    signal closed

    // Sets the opening text without treating it as a title edit.
    function setText(text: string) {
        titleInput.setPlainText(text);
    }

    // Existing items show the title from its start. New items get the cursor.
    function begin(existing: bool) {
        if (existing) {
            titleInput.cursorPosition = 0;
            titleFlick.contentY = 0;
            return;
        }
        Qt.callLater(function () {
            titleInput.forceActiveFocus();
            titleInput.cursorPosition = titleInput.text.length;
        });
    }

    // Gives up the title cursor when the form or panel closes.
    function releaseFocus() {
        titleInput.focus = false;
    }

    height: titleHeight

    readonly property real singleLine: 40
    readonly property int maxLines: 3
    readonly property int growLines: 6
    // Height the title box may take: the body height minus everything else in it.
    onAvailableHeightChanged: refit()
    readonly property int normalSize: 24
    readonly property int minSize: Math.ceil(normalSize * 0.6)
    // Vertical space around the text lines, from the normal size.
    readonly property real framePadding: singleLine - normalMetrics.height

    // The font size that fits, and the box height for it. Both are set by refit().
    property int fitSize: normalSize
    property real wantedHeight: singleLine
    property real titleHeight: wantedHeight
    // The size on screen; it follows fitSize smoothly.
    property real shownSize: fitSize

    Behavior on titleHeight {
        StandardMotion { duration: Theme.hoverMs }
    }

    Behavior on shownSize {
        StandardMotion { duration: Theme.hoverMs }
    }

    // Picks the biggest size (normal down to minimum) where the text needs 3 lines or fewer.
    // It runs when the text or the width changes, never per frame.
    function refit() {
        if (titleFlick.width <= 0) return;
        probe.text = titleInput.text;
        var size = normalSize;
        var lineHeight = 0;
        var lines = 1;
        for (; size >= minSize; size--) {
            probe.font.pixelSize = size;
            lineHeight = probeMetrics.height;
            lines = Math.max(1, Math.round(probe.contentHeight / lineHeight));
            if (lines <= maxLines) break;
        }
        if (size < minSize) size = minSize;
        fitSize = size;
        var capacity = maxLines;
        if (lines > maxLines) {
            var free = Math.floor((availableHeight - framePadding) / lineHeight);
            capacity = Math.max(maxLines, Math.min(growLines, free));
        }
        wantedHeight = framePadding + Math.min(lines, capacity) * lineHeight;
    }

    onFramePaddingChanged: refit()

    FontMetrics {
        id: normalMetrics
        font.family: Theme.condensed
        font.pixelSize: root.normalSize
        font.weight: Font.Medium
    }

    // Hidden copy of the title used only to measure how many lines a size needs.
    Text {
        textFormat: Text.PlainText
        id: probe
        width: titleFlick.width
        visible: false
        wrapMode: Text.Wrap
        font.family: Theme.condensed
        font.weight: Font.Medium
        font.letterSpacing: -0.24 * root.fitSize / root.normalSize
    }

    FontMetrics {
        id: probeMetrics
        font: probe.font
    }

    Flickable {
        id: titleFlick
        anchors.left: parent.left
        anchors.right: closeButton.left
        anchors.rightMargin: 8
        anchors.leftMargin: 2
        height: parent.height
        contentWidth: width
        onWidthChanged: root.refit()
        contentHeight: titleInput.height
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        opacity: root.readOnly ? 0.55 : 1

        Fade on opacity { duration: Theme.stateMs }

        // Keeps the caret in view when the title has more lines than the box (only while typing).
        function showCaret() {
            var r = titleInput.cursorRectangle;
            if (r.y < contentY) contentY = r.y;
            else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height;
        }

        // The mouse wheel scrolls a title that has more lines than the box at the minimum size.
        WheelHandler {
            onWheel: event => {
                var max = Math.max(0, titleFlick.contentHeight - titleFlick.height);
                titleFlick.contentY = Math.max(0, Math.min(max, titleFlick.contentY - event.angleDelta.y / 2));
            }
        }

        TextEdit {
            id: titleInput

            // Set while code (not the user) changes the text.
            property bool settingText: false

            // Sets the text without reading it as typed natural text.
            function setPlainText(value: string) {
                settingText = true;
                text = value;
                settingText = false;
            }

            width: titleFlick.width
            height: Math.max(implicitHeight, root.singleLine * root.shownSize / root.normalSize)
            topPadding: root.framePadding / 2
            bottomPadding: topPadding
            wrapMode: TextEdit.Wrap
            enabled: !root.readOnly
            activeFocusOnTab: true
            selectByMouse: true
            font.family: Theme.condensed
            font.pixelSize: Math.round(root.shownSize)
            font.weight: Font.Medium
            font.letterSpacing: -0.24 * root.shownSize / root.normalSize
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            cursorDelegate: Rectangle { width: 1; color: Theme.accentLight }

            // A typed or pasted line break becomes a space. Enter saves (below).
            onTextChanged: {
                root.refit();
                if (!activeFocus) titleFlick.contentY = 0;
                if (settingText) return;
                if (text.indexOf("\n") >= 0) {
                    var at = cursorPosition;
                    settingText = true;
                    text = text.replace(/[\r\n]+/g, " ");
                    settingText = false;
                    cursorPosition = Math.min(at, text.length);
                }
                root.edited(text);
            }
            onCursorRectangleChanged: titleFlick.showCaret()
            // Without focus the title shows from its start.
            onActiveFocusChanged: if (!activeFocus) titleFlick.contentY = 0
            Keys.onReturnPressed: root.accepted()
            Keys.onEnterPressed: root.accepted()
            Keys.onEscapePressed: root.escaped()

            Text {
                textFormat: Text.PlainText
                visible: titleInput.text === ""
                y: titleInput.topPadding
                text: "Title"
                font: titleInput.font
                color: Theme.mute
            }
        }
    }

    // Underline: 1px border, 2px accent while focused.
    Rectangle {
        anchors.left: parent.left
        anchors.right: closeButton.left
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        height: titleInput.activeFocus ? 2 : 1
        color: titleInput.activeFocus ? Theme.accent : Theme.border

        ColorFade on color {}
    }

    HoverButton {
        id: closeButton
        anchors.right: parent.right
        anchors.top: parent.top
        width: 26
        height: 26
        icon: "x"
        iconSize: 14
        iconStrokeWidth: 1.8
        textColor: Theme.dim
        onClicked: root.closed()
    }
}
