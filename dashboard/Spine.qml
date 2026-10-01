import QtQuick
import qs.common
import qs.pill
import qs.services

/**
 * Right-hand spine column of the open panel: one icon button per tab stacked
 * above a vertical label. The button at `activeTab` gets the active style
 * and its label shows in the vertical text; clicking a button emits `tabClicked`.
 */
Item {
    id: root

    readonly property int buttonSize: 48

    /** The tabs in spine order; each has an `icon` (Lucide name) and a `label`. Set by Pill.qml. */
    required property var tabs

    /** Index of the active tab (set by Pill.qml). */
    property int activeTab: 0

    /** Emitted with the button index when the user clicks a tab icon. */
    signal tabClicked(int index)

    // Right edge of the panel: rounds its two outer (right-side) corners
    // to match the frame's inset radius; left corners stay square (inner seam).
    Rectangle {
        anchors.fill: parent
        color: Theme.shell
        topRightRadius: 7
        bottomRightRadius: 7
    }

    Column {
        id: buttonColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Repeater {
            id: repeater
            model: root.tabs

            delegate: Rectangle {
                id: tabButton
                required property var modelData
                required property int index

                readonly property bool active: index === root.activeTab

                width: root.width
                height: root.buttonSize
                color: active ? Theme.card : (hover.hovered ? Theme.sunk : Qt.rgba(Theme.sunk.r, Theme.sunk.g, Theme.sunk.b, 0))
                // Top button sits flush against the frame's rounded top-right corner.
                topRightRadius: index === 0 ? 7 : 0

                ColorFade on color {}

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 2
                    color: tabButton.active ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0)

                    ColorFade on color { duration: Theme.stateMs }
                }

                HoverHandler { id: hover }
                MouseArea { anchors.fill: parent; onClicked: root.tabClicked(tabButton.index) }

                Icon {
                    anchors.centerIn: parent
                    name: tabButton.modelData.icon
                    size: 19
                    strokeWidth: 1.5
                    color: tabButton.active ? Theme.accentLight : (hover.hovered ? Theme.fg2 : Theme.dim)

                    ColorFade on color {}
                }
            }
        }
    }

    // Vertical tab label, bottom-anchored, read bottom-to-top (a -90
    // degree rotation turns left-to-right text into bottom-to-top).
    Item {
        id: labelArea
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: labelText.implicitHeight
        height: labelText.implicitWidth

        // Text on screen; follows the active tab's label after a short fade out.
        property string shownText: root.tabs[0].label
        readonly property string wantedText: root.tabs[root.activeTab].label
        onWantedTextChanged: labelSwap.restart()

        // Fade out, swap the text, fade in. Not a Behavior: the swap must
        // happen at the low point of the fade.
        SequentialAnimation {
            id: labelSwap
            NumberAnimation { target: labelText; property: "opacity"; to: 0; duration: 120 }
            ScriptAction { script: labelArea.shownText = labelArea.wantedText }
            NumberAnimation { target: labelText; property: "opacity"; to: 1; duration: 180 }
        }

        MonoText {
            id: labelText
            anchors.centerIn: parent
            rotation: -90
            text: labelArea.shownText
            font.pixelSize: 10
            font.letterSpacing: 2.4
        }
    }
}
