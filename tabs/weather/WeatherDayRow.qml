import QtQuick
import "../../logic/WeatherFormat.js" as Fmt
import qs.common
import qs.services

/**
 * One row of the 7-day column: day name, condition icon, chance of rain
 * (from 30%), low and high. The selected row gets a soft accent fill and an
 * accent bar on its left edge; both fade with one progress value.
 */
Rectangle {
    id: root

    /** One entry of Weather.days. */
    property var day
    property bool today: false
    property bool selected: false

    signal clicked

    /** 0 not selected, 1 selected. */
    property real pick: root.selected ? 1 : 0

    Behavior on pick {
        StandardMotion {
            duration: 200
        }
    }

    color: Theme.card

    Rectangle {
        anchors.fill: parent
        color: Theme.raised
        opacity: hover.containsMouse && !root.selected ? 1 : 0
        Fade on opacity {}
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.selectionSoft
        opacity: root.pick
    }

    Rectangle {
        width: 2
        height: parent.height
        color: Theme.accentLight
        opacity: root.pick
    }

    CondensedText {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.today ? "TODAY" : Fmt.weekday(root.day.date)
        font.pixelSize: 16
        color: Qt.tint(Theme.fg, Qt.rgba(Theme.accentLight.r, Theme.accentLight.g, Theme.accentLight.b, root.pick))
    }

    Icon {
        x: 14 + 48 + 10
        anchors.verticalCenter: parent.verticalCenter
        name: Weather.iconForGroup(Weather.weatherGroup(root.day.code), true)
        size: 18
        strokeWidth: 1.6
        color: Theme.dim
    }

    MonoText {
        x: 14 + 48 + 10 + 20 + 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.day.precipProbability >= 30 ? root.day.precipProbability + "%" : ""
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        CondensedText {
            anchors.baseline: high.baseline
            text: Math.round(root.day.minC) + "°"
            font.pixelSize: 14
            color: Theme.dim
        }
        CondensedText {
            id: high
            width: Math.max(26, implicitWidth)
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.day.maxC) + "°"
            font.pixelSize: 20
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
