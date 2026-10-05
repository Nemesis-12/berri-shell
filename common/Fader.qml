import QtQuick
import qs.services

/** A vertical meter with clipped text. The expanded form matches the Media tab. */
Item {
    id: root

    /** System value in percent. User input never replaces this binding. */
    property real value: 0
    property string iconName: "sun"
    property string label: "BRIGHT"
    property bool expanded: false

    property bool dragging: false
    property real draggedValue: 0
    readonly property real displayValue: dragging ? draggedValue : Math.max(0, Math.min(100, value))
    property real fillValue: displayValue
    readonly property string numberText: Math.round(expanded && !dragging ? fillValue : displayValue).toString()
    readonly property real labelLetterSpacing: 9 * 0.12

    signal valueEdited(real newValue)

    Behavior on fillValue {
        enabled: !root.dragging
        StandardMotion {
            duration: Theme.stateMs
        }
    }

    // Both text layers have the same geometry. Only their colors differ.
    component MeterText: Item {
        property color textColor: Theme.fg
        property color detailColor: Theme.dim

        Text {
            textFormat: Text.PlainText
            x: root.expanded ? 12 : 10
            y: root.expanded ? 4 : 10
            height: root.expanded ? 34 : implicitHeight
            text: root.numberText
            font.family: Theme.condensed
            font.weight: Font.Medium
            font.pixelSize: root.expanded ? 40 : 22
            lineHeightMode: root.expanded ? Text.FixedHeight : Text.ProportionalHeight
            lineHeight: root.expanded ? 34 : 1
            color: parent.textColor
        }

        Row {
            visible: !root.expanded
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: 10
            anchors.leftMargin: 10
            spacing: 6

            Icon {
                name: root.iconName
                size: 15
                strokeWidth: 1.5
                color: parent.parent.detailColor
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                textFormat: Text.PlainText
                text: root.label
                font.family: Theme.mono
                font.weight: Font.DemiBold
                font.pixelSize: 9
                font.letterSpacing: root.labelLetterSpacing
                color: parent.parent.detailColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Column {
            visible: root.expanded
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 10

            SideLabel {
                text: root.label
                tone: parent.parent.detailColor
                weight: Font.DemiBold
            }
            Icon {
                name: root.iconName
                size: 17
                strokeWidth: 1.8
                color: parent.parent.detailColor
            }
        }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: root.expanded ? 0 : 4
        color: root.expanded ? Theme.card : Theme.raised
        clip: true

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: track.height * root.fillValue / 100
            color: root.expanded ? Theme.accentLight : Theme.accent

            Rectangle {
                visible: !root.expanded
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 2
                color: Theme.accentLight
            }
        }

        MeterText {
            anchors.fill: parent
            detailColor: root.expanded ? Theme.fg : Theme.dim
        }

        Item {
            id: accentClip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: fill.height
            clip: true

            MeterText {
                y: accentClip.height - track.height
                width: track.width
                height: track.height
                textColor: Theme.onAccent
                detailColor: Theme.onAccent
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            // A press or drag edits local state and sends the value to its owner.
            function setFromY(y) {
                root.draggedValue = Math.max(0, Math.min(100, 100 * (1 - y / height)));
                root.valueEdited(root.draggedValue);
            }

            onPressed: mouse => {
                root.dragging = true;
                setFromY(mouse.y);
            }
            onPositionChanged: mouse => { if (pressed) setFromY(mouse.y); }
            onReleased: root.dragging = false
            onCanceled: root.dragging = false
        }
    }
}
