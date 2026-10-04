import QtQuick
import Quickshell
import qs.services
import qs.common

/**
 * An app's right-click menu drawn in berri's style (mock Tray B menu).
 * Entries with children open in place; the title row goes back one level.
 */
PillTrayPopover {
    id: root

    /** The QsMenuHandle of the tray item. */
    property var handle: null
    property string title: ""

    /** Emitted after an entry ran; the owner closes the layers. */
    signal finished()

    pivot: Item.TopLeft
    width: 164
    height: column.implicitHeight + 14

    // Entries opened so far (submenus), innermost last.
    property var path: []
    readonly property var current: path.length > 0 ? path[path.length - 1] : handle
    readonly property string heading: path.length > 0 ? path[path.length - 1].text : title

    onOpenChanged: if (open) path = []

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    Column {
        id: column
        x: 7
        y: 7
        width: parent.width - 14
        spacing: 1

        // Title row: the app name, or "<" plus the submenu name.
        Item {
            width: parent.width
            height: 25

            Text {
                textFormat: Text.PlainText
                x: 8
                y: 6
                width: parent.width - 16
                text: (root.path.length > 0 ? "‹  " : "") + root.heading.toUpperCase()
                elide: Text.ElideRight
                font.family: Theme.mono
                font.weight: Font.DemiBold
                font.pixelSize: 10
                font.letterSpacing: 0.76
                color: Theme.dim
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.path.length > 0
                onClicked: root.path = root.path.slice(0, -1)
            }
        }

        Repeater {
            model: opener.children

            delegate: Item {
                id: entryRow
                required property var modelData

                width: column.width
                height: modelData.isSeparator ? 7 : 30

                Rectangle {
                    visible: entryRow.modelData.isSeparator
                    x: 6
                    y: 3
                    width: parent.width - 12
                    height: 1
                    color: Theme.border
                }

                Rectangle {
                    visible: !entryRow.modelData.isSeparator
                    anchors.fill: parent
                    radius: 5
                    color: rowHover.hovered && entryRow.modelData.enabled ? PillTrayStyle.hoverFill : PillTrayStyle.hoverFillClear
                    ColorFade on color {}

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        width: parent.width - 34
                        text: entryRow.modelData.text
                        elide: Text.ElideRight
                        font.family: Theme.condensed
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                        color: Theme.fg
                        opacity: entryRow.modelData.enabled ? 1 : 0.4
                    }

                    // Submenu arrow, or a check mark for a ticked entry.
                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: entryRow.modelData.hasChildren ? "›"
                            : (entryRow.modelData.checkState === Qt.Checked ? "✓" : "")
                        font.family: Theme.mono
                        font.pixelSize: 11
                        color: entryRow.modelData.hasChildren ? Theme.dim : Theme.accentLight
                    }

                    HoverHandler { id: rowHover }

                    MouseArea {
                        anchors.fill: parent
                        enabled: entryRow.modelData.enabled
                        onClicked: {
                            if (entryRow.modelData.hasChildren) {
                                root.path = root.path.concat([entryRow.modelData]);
                            } else {
                                entryRow.modelData.triggered();
                                root.finished();
                            }
                        }
                    }
                }
            }
        }
    }
}
