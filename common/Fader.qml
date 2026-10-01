import QtQuick
import qs.services

/**
 * One vertical fader (ticket 19): a rounded track filled from the bottom to
 * `value` percent. The number and the icon/label are drawn twice — once in
 * their normal color, once in Theme.onAccent clipped to the fill's height —
 * so the part covered by the fill switches color, mirroring the mock's
 * clip-path trick. Drag (or a single press) anywhere sets the value.
 */
Item {
    id: root

    property real value: 0          // 0-100, the displayed/target value
    property string iconName: "sun"
    property string label: "BRIGHT"
    property bool dragging: false

    signal valueEdited(real newValue)  // user set a value by press/drag, 0-100

    readonly property string numberText: Math.round(Math.max(0, Math.min(100, value))).toString()
    readonly property real labelLetterSpacing: 9 * 0.12

    Rectangle {
        id: track
        anchors.fill: parent
        radius: 4
        color: Theme.raised
        clip: true

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: track.height * Math.max(0, Math.min(100, root.value)) / 100
            color: Theme.accent

            Behavior on height {
                enabled: !root.dragging
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.standardCurve
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 2
                color: Theme.accentLight
            }
        }

        // Normal-color number (top-left) and icon+label (bottom-left).
        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: 10
            anchors.leftMargin: 10
            text: root.numberText
            font.family: Theme.condensed
            font.weight: Font.Medium
            font.pixelSize: 22
            color: Theme.fg
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: 10
            anchors.leftMargin: 10
            spacing: 6

            Icon {
                name: root.iconName
                size: 15
                strokeWidth: 1.5
                color: Theme.dim
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.label
                font.family: Theme.mono
                font.weight: Font.DemiBold
                font.pixelSize: 9
                font.letterSpacing: root.labelLetterSpacing
                color: Theme.dim
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Same content again in Theme.onAccent, clipped to the fill's height
        // so only the part covered by the fill shows through.
        Item {
            id: accentClip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: fill.height
            clip: true

            Item {
                x: 0
                y: accentClip.height - track.height
                width: track.width
                height: track.height

                Text {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: 10
                    anchors.leftMargin: 10
                    text: root.numberText
                    font.family: Theme.condensed
                    font.weight: Font.Medium
                    font.pixelSize: 22
                    color: Theme.onAccent
                }

                Row {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.bottomMargin: 10
                    anchors.leftMargin: 10
                    spacing: 6

                    Icon {
                        name: root.iconName
                        size: 15
                        strokeWidth: 1.5
                        color: Theme.onAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.label
                        font.family: Theme.mono
                        font.weight: Font.DemiBold
                        font.pixelSize: 9
                        font.letterSpacing: root.labelLetterSpacing
                        color: Theme.onAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            function setFromY(y) {
                var v = 100 * (1 - y / track.height);
                root.valueEdited(Math.max(0, Math.min(100, v)));
            }

            onPressed: mouse => {
                root.dragging = true;
                setFromY(mouse.y);
            }
            onPositionChanged: mouse => {
                if (pressed)
                    setFromY(mouse.y);
            }
            onReleased: root.dragging = false
            onCanceled: root.dragging = false
        }
    }
}
