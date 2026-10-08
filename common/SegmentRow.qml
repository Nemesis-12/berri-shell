import QtQuick
import qs.services

// A few choices on a border grid, in equal cells, with a fill and top bar for the selection.
Rectangle {
    id: seg

    property var options: []
    property string current: ""
    property int cellHeight: 28
    property real spacingText: 0.72
    signal picked(string key)

    height: cellHeight + 2
    color: Theme.border

    Row {
        x: 1
        y: 1
        spacing: 1

        Repeater {
            model: seg.options

            delegate: Rectangle {
                id: cell

                required property var modelData
                readonly property bool chosen: modelData.key === seg.current
                readonly property color tint: Theme.accent
                readonly property color soft: Theme.selectionSoft

                width: (seg.width - 2 - (seg.options.length - 1)) / seg.options.length
                height: seg.cellHeight
                color: chosen ? soft : Qt.rgba(soft.r, soft.g, soft.b, 0)

                ColorFade on color { duration: Theme.stateMs }

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 2
                    color: cell.tint
                    opacity: cell.chosen ? 1 : 0

                    Fade on opacity { duration: Theme.stateMs }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    MonoText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cell.modelData.label.toUpperCase()
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: seg.spacingText
                        color: cell.chosen ? Theme.accentLight : Theme.dim

                        ColorFade on color { duration: Theme.stateMs }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(cell.modelData.key)
                }
            }
        }
    }
}
