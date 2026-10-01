import QtQuick
import qs.services

/**
 * One row in a device list (Wi-Fi networks, Bluetooth devices): a 32px
 * clickable row with a highlighted background while `active`, a bottom
 * divider, and a small mono tag on the right. Row-specific content (an
 * icon and a label, or a password field) goes in the default content area
 * on the left, laid out in a Row.
 */
Rectangle {
    id: root

    property bool active: false
    property bool rowEnabled: true
    property string tagText: ""
    property color tagColor: Theme.dim

    signal clicked

    default property alias content: contentRow.data

    height: 32
    color: active ? Theme.accentFill : (rowMouse.containsMouse ? Theme.raised : "transparent")

    ColorFade on color {}

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    Row {
        id: contentRow
        anchors.left: parent.left
        anchors.right: tag.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 6
        spacing: 10
    }

    MonoText {
        id: tag
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        font.letterSpacing: 0.08 * 9
        text: root.tagText
        color: root.tagColor
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.rowEnabled
        onClicked: root.clicked()
    }
}
