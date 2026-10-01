import QtQuick
import qs.common
import qs.services

/** One figure of the code tab's stats column: a small mono label over a big condensed value. */
Rectangle {
    id: root

    property string label: ""
    property string value: "--"

    /** Optional small line under the value, like "7.19M tokens". */
    property string sub: ""

    color: Theme.card

    Column {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        MonoText {
            text: root.label
            font.letterSpacing: 0.9
        }

        Item {
            width: valueText.implicitWidth
            height: 18
            CodeValue {
                id: valueText
                anchors.verticalCenter: parent.verticalCenter
                value: root.value
                font.pixelSize: 21
                font.letterSpacing: -0.21
            }
        }

        CodeValue {
            visible: root.sub !== ""
            value: root.sub
            color: Theme.dim
            font.family: Theme.mono
            font.weight: Font.Medium
            font.pixelSize: 9
        }
    }
}
