import QtQuick
import qs.services

/** Home uses the shared brightness service and volume control. */
Item {
    id: root

    WhileVisible { service: Brightness }
    Component.onDestruction: if (brightnessFader.dragging) Brightness.dragging = false

    Row {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Fader {
            id: brightnessFader
            width: (parent.width - 6) / 2
            height: parent.height
            value: Brightness.value
            iconName: "sun"
            label: "BRIGHT"
            onValueEdited: newValue => Brightness.setValue(newValue)
            onDraggingChanged: Brightness.dragging = dragging
        }

        VolumeFader {
            width: (parent.width - 6) / 2
            height: parent.height
        }
    }
}
