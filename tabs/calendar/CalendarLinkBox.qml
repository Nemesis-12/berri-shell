import QtQuick
import qs.common
import qs.services

/** Link entry, import and subscribe actions, and their hint. */
// Link box: padding 10 12 12, 34px row, 8px gap, 9px hint line.
Item {
    id: root
    property string newColor
    property bool canSubscribe
    property string hintText
    property color hintColor
    property alias text: linkInput.text
    readonly property bool textEntryActive: linkInput.activeFocus

    signal textEdited
    signal subscribeRequested
    signal resetRequested
    signal importRequested
    signal colorRequested(Item square)

    /** Gives up link entry focus when the panel closes. */
    function releaseFocus() {
        linkInput.focus = false;
    }

    /** True when the scene point is inside the link entry box. */
    function containsLink(scenePoint): bool {
        var point = linkBox.mapFromItem(null, scenePoint.x, scenePoint.y);
        return point.x >= 0 && point.y >= 0 && point.x <= linkBox.width && point.y <= linkBox.height;
    }

    height: 10 + 34 + 8 + 9 + 12

    // Color of the next calendar; click opens the popover.
    Rectangle {
        id: newColorBox
        x: 12
        y: 10
        width: 34
        height: 34
        color: Theme.shell

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.accentLine
        }

        CalendarSwatch {
            id: newColorSwatch
            anchors.centerIn: parent
            colorKey: root.newColor
            interactive: false
            // The swatch's own area is off; the box below takes the click.
        }

        MouseArea {
            id: newColorMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.colorRequested(newColorBox)
        }

        Rectangle {
            anchors.fill: newColorSwatch
            color: "white"
            opacity: newColorMouse.containsMouse ? 0.14 : 0

            Fade on opacity {}
        }
    }

    Rectangle {
        id: linkBox
        x: 12 + newColorBox.width + 1
        y: 10
        width: parent.width - 24 - newColorBox.width - 1 - importButton.width - subscribeButton.width - 2
        height: 34
        color: Theme.shell

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.accentLine
        }

        Text {
            id: prompt
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            font.family: Theme.mono
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Theme.accentLight
        }

        Text {
            anchors.left: prompt.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: linkInput.text === ""
            text: "paste a link"
            font.family: Theme.mono
            font.pixelSize: 12
            font.weight: Font.Medium
            color: Theme.mute
        }

        TextInput {
            id: linkInput
            anchors.left: prompt.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            selectByMouse: true
            font.family: Theme.mono
            font.pixelSize: 12
            font.weight: Font.Medium
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            cursorDelegate: Rectangle { width: 1; color: Theme.accentLight }
            onTextEdited: root.textEdited()
            Keys.onReturnPressed: root.subscribeRequested()
            Keys.onEnterPressed: root.subscribeRequested()
            Keys.onEscapePressed: root.resetRequested()
        }

        // Click anywhere on the box to type.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: linkInput.forceActiveFocus()
        }
    }

    HoverButton {
        id: importButton
        anchors.left: linkBox.right
        anchors.leftMargin: 1
        y: 10
        height: 34
        width: implicitWidth
        sidePadding: 10
        label: "IMPORT FILE"
        fill: Theme.raised
        textColor: Theme.fg2
        hoverTextColor: Theme.fg2
        onClicked: root.importRequested()
    }

    Rectangle {
        id: subscribeButton
        anchors.left: importButton.right
        anchors.leftMargin: 1
        y: 10
        height: 34
        width: subscribeText.implicitWidth + 24
        color: subscribeMouse.containsMouse && root.canSubscribe ? Theme.accentLight : Theme.accent
        opacity: root.canSubscribe ? 1 : 0.45

        ColorFade on color {}

        Fade on opacity { duration: Theme.stateMs }

        Text {
            id: subscribeText
            anchors.centerIn: parent
            text: "SUBSCRIBE"
            font.family: Theme.mono
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 1.26
            color: Theme.onAccent
        }

        MouseArea {
            id: subscribeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.canSubscribe ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.subscribeRequested()
        }
    }

    Item {
        x: 12
        y: 10 + 34 + 8
        width: parent.width - 24
        height: 9

        MonoText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            elide: Text.ElideRight
            text: root.hintText
            font.pixelSize: 9
            font.weight: Font.Medium
            font.letterSpacing: 0.18
            color: root.hintColor

            ColorFade on color { duration: Theme.stateMs }
        }
    }
}
