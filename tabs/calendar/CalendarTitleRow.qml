import QtQuick
import "../../logic/Times.js" as Times
import qs.common
import qs.services

/**
 * Title row of the calendar month card: month, year, previous, today and next.
 * Set `viewYear` and `viewMonth`; answer the three signals to change the month.
 */
Item {
    id: root

    /** Month shown: full year and month number 0..11. */
    required property int viewYear
    required property int viewMonth

    signal previousRequested
    signal todayRequested
    signal nextRequested

    height: 56

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: prevButton.left
        anchors.rightMargin: 1
        color: Theme.card
        topLeftRadius: 7

        // Both texts sit in boxes as tall as their CSS line (34px and 10px) and are centered in the row.
        Item {
            id: monthBox
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: monthText.implicitWidth
            height: 34

            Text {
                textFormat: Text.PlainText
                id: monthText
                anchors.verticalCenter: parent.verticalCenter
                text: Times.monthsLong[root.viewMonth].toUpperCase()
                font.family: Theme.condensed
                font.pixelSize: 34
                font.weight: Font.Medium
                font.letterSpacing: -0.68
                color: Theme.fg
            }
        }

        Item {
            x: monthBox.x + monthBox.width + 10
            anchors.verticalCenter: parent.verticalCenter
            width: yearText.implicitWidth
            height: 10

            MonoText {
                id: yearText
                anchors.verticalCenter: parent.verticalCenter
                text: root.viewYear
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 1.2
                color: Theme.dim
            }
        }
    }

    // Month navigation with the same label and icon measurements.
    component HeaderButton: HoverButton {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        fill: Theme.card
        hoverFill: Theme.raised
        textColor: Theme.fg2
        hoverTextColor: Theme.fg2
        fontSize: 10
        letterSpacing: 1.4
        iconSize: 17
        iconStrokeWidth: 1.6
    }

    HeaderButton {
        id: prevButton
        anchors.right: todayButton.left
        anchors.rightMargin: 1
        width: 48
        icon: "chevron-left"
        onClicked: root.previousRequested()
    }

    HeaderButton {
        id: todayButton
        anchors.right: nextButton.left
        anchors.rightMargin: 1
        width: todayMetrics.implicitWidth + 28
        label: "TODAY"
        onClicked: root.todayRequested()

        MonoText {
            id: todayMetrics
            visible: false
            text: "TODAY"
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: 1.4
        }
    }

    HeaderButton {
        id: nextButton
        anchors.right: parent.right
        width: 48
        icon: "chevron-right"
        onClicked: root.nextRequested()
    }
}
