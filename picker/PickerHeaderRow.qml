import QtQuick
import qs.common
import qs.services

/**
 * Header row of the open picker: the Themes / Wallpapers tabs, the sub line,
 * the key hint and the close button. Set `pickerTab`; answer `tabClicked`
 * and `closeClicked`. The notch sets the anchors and the height.
 */
Item {
    id: root

    /** The tab showing: "themes" or "walls". */
    required property string pickerTab

    signal tabClicked(string key)
    signal closeClicked

    // Segmented Themes/Wallpapers tabs.
    Rectangle {
        id: tabsBg
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: tabsRow.width + 6
        height: 34
        radius: 5
        color: Theme.card

        Row {
            id: tabsRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: [
                    { key: "themes", label: "Themes" },
                    { key: "walls", label: "Wallpapers" }
                ]

                delegate: Rectangle {
                    id: tabBtn
                    required property var modelData
                    readonly property bool active: root.pickerTab === modelData.key
                    width: tabLabel.implicitWidth + 28
                    height: 28
                    radius: 5
                    color: active ? Theme.accent : "transparent"
                    ColorFade on color { duration: Theme.stateMs }

                    Text {
                        textFormat: Text.PlainText
                        id: tabLabel
                        anchors.centerIn: parent
                        text: tabBtn.modelData.label
                        font.family: Theme.condensed
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                        color: tabBtn.active ? Theme.onAccent : Theme.dim
                        ColorFade on color { duration: Theme.stateMs }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tabClicked(tabBtn.modelData.key)
                    }
                }
            }
        }
    }

    // Sub line: e.g. "Wine Lilac applied · 9 themes".
    Text {
        textFormat: Text.PlainText
        id: subLabel
        anchors.left: tabsBg.right
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.mono
        font.weight: Font.Medium
        font.pixelSize: 10
        color: Theme.dim
        text: {
            var cur = Theme.current;
            if (!cur) return "";
            return root.pickerTab === "themes"
                ? (cur.name + " applied · " + Theme.palettes.length + " themes")
                : ("Saved for " + cur.name);
        }
    }

    // Close button (28x28, Lucide x).
    Rectangle {
        id: closeBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        radius: 5
        color: closeArea.containsMouse ? Theme.raised : "transparent"
        ColorFade on color {}

        Icon {
            anchors.centerIn: parent
            name: "x"
            size: 13
            strokeWidth: 2.2
            color: closeArea.containsMouse ? Theme.fg : Theme.dim
            ColorFade on color {}
        }

        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeClicked()
        }
    }

    // Hint text, right of the sub line, left of the close button.
    Text {
        textFormat: Text.PlainText
        anchors.right: closeBtn.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.mono
        font.weight: Font.Medium
        font.pixelSize: 10
        color: Theme.dim
        text: "← → browse · Enter apply · Esc close"
    }
}
