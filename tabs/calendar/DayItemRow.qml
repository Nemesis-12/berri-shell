import QtQuick
import QtQuick.Layouts
import "../../logic/Times.js" as Times
import qs.common
import qs.services

/** One day item, with its time, actions and drag movement. */
Item {
    id: row

    property string shownKey: ""
    property bool shownIsToday: false
    property string nowTime: ""
    property bool clock24: false
    property int dragThreshold: 5

    signal itemClicked(string uid, string occurrenceDate)
    signal dragStarted(var info)
    signal dragMoved(point scenePoint)
    signal dragFinished(point scenePoint)
    signal dragAborted

    required property string key
    required property string uid
    required property string kind
    required property string title
    required property string tintKey
    required property string occurrenceDate
    required property string time
    required property string end
    required property bool recurring
    required property string repeat
    required property bool done
    required property bool readOnly
    required property string calendarName

    readonly property bool isTask: kind === "task"
    readonly property bool isReminder: kind === "reminder"
    readonly property bool isAllDay: kind === "event" && time === ""
    readonly property color tint: CalendarColors.resolve(tintKey)
    readonly property bool due: isReminder && !done && row.shownIsToday && time !== "" && time <= row.nowTime
    readonly property string typeLabel: isTask ? "Task" : isReminder ? "Reminder" : isAllDay ? "All-day" : "Event"
    readonly property string repeatLabel: repeat === "none" ? "" : repeat.charAt(0).toUpperCase() + repeat.slice(1)
    // "10:00 AM · UNTIL 11:00 AM" and the like.
    readonly property string meta: [
        isAllDay ? "All day" : (time !== "" ? Times.clockText(time, row.clock24) : "—"),
        readOnly ? calendarName : ((kind === "event" && end !== "") ? "until " + Times.clockText(end, row.clock24) : typeLabel),
        readOnly ? "" : repeatLabel,
        due ? "Due now" : ""
    ].filter(function (part) { return part !== ""; }).join(" · ").toUpperCase()

    width: ListView.view.width
    height: 52

    Rectangle {
        anchors.fill: parent
        color: row.due ? Theme.accentFill : (rowMouse.containsMouse ? Theme.raised : "transparent")

        ColorFade on color {}
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    // Click opens the item. Press and move past the threshold drags it to a day.
    MouseArea {
        id: rowMouse

        property bool dragging: false
        property bool moved: false
        property point pressAt

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        onPressed: mouse => {
            pressAt = Qt.point(mouse.x, mouse.y);
            moved = false;
            dragging = false;
        }
        onPositionChanged: mouse => {
            if (!pressed || row.readOnly) return;
            if (!dragging) {
                if (Math.hypot(mouse.x - pressAt.x, mouse.y - pressAt.y) < row.dragThreshold) return;
                dragging = true;
                moved = true;
                row.dragStarted({
                    shape: "row",
                    fromKey: row.shownKey,
                    uid: row.uid,
                    occurrenceDate: row.occurrenceDate,
                    title: row.title,
                    meta: row.meta,
                    done: row.done,
                    tint: row.tint,
                    width: row.width,
                    height: row.height,
                    grab: pressAt,
                    origin: row.mapToItem(null, 0, 0)
                });
            }
            row.dragMoved(mapToItem(null, mouse.x, mouse.y));
        }
        onReleased: mouse => {
            if (!dragging) return;
            dragging = false;
            row.dragFinished(mapToItem(null, mouse.x, mouse.y));
        }
        onCanceled: {
            if (!dragging) return;
            dragging = false;
            row.dragAborted();
        }
        onClicked: if (!moved) row.itemClicked(row.uid, row.occurrenceDate)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 5
        anchors.topMargin: 6
        anchors.bottomMargin: 7
        spacing: 10

        // Marker: checkbox (task), bell (reminder) or square (event).
        Item {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                visible: row.isTask
                anchors.fill: parent
                color: row.done ? row.tint : "transparent"
                border.width: 1.5
                border.color: row.tint

                ColorFade on color { duration: Theme.stateMs }

                Icon {
                    anchors.centerIn: parent
                    name: "check"
                    size: 11
                    strokeWidth: 3.2
                    color: Theme.onAccent
                    opacity: row.done ? 1 : 0

                    Fade on opacity { duration: Theme.stateMs }
                }
            }

            Icon {
                visible: row.isReminder
                anchors.centerIn: parent
                name: "bell"
                size: 16
                strokeWidth: 1.8
                color: row.tint
                opacity: row.done ? 0.35 : 1

                Fade on opacity { duration: Theme.stateMs }
            }

            Rectangle {
                visible: !row.isTask && !row.isReminder
                anchors.centerIn: parent
                width: 8
                height: 8
                color: row.tint
            }

            MouseArea {
                anchors.fill: parent
                visible: (row.isTask || row.isReminder) && !row.readOnly
                cursorShape: Qt.PointingHandCursor
                onClicked: Calendar.setDone(row.uid, !row.done, row.occurrenceDate)
            }
        }

        // Title and meta sit in boxes as tall as their CSS lines (14px x 1.1 and 9px), 4px apart.
        Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            Item {
                width: parent.width
                height: 15.4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    text: row.title
                    elide: Text.ElideRight
                    font.family: Theme.condensed
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    font.strikeout: row.done
                    color: row.done ? Theme.mute : Theme.fg

                    ColorFade on color { duration: Theme.stateMs }
                }
            }

            Item {
                width: parent.width
                height: 9

                MonoText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    text: row.meta
                    elide: Text.ElideRight
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: 0.36
                    color: Theme.dim
                }
            }
        }

        // Snooze chips (reminders only).
        Row {
            visible: row.isReminder && !row.readOnly
            spacing: 1
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: [{ label: "+15M", amount: 15 }, { label: "+1D", amount: "1d" }]

                delegate: Rectangle {
                    id: chip

                    required property var modelData

                    height: 24
                    width: chipText.implicitWidth + 10
                    color: row.due ? Theme.accent : Theme.hover

                    ColorFade on color { duration: Theme.stateMs }

                    MonoText {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        color: row.due ? Theme.onAccent : Theme.dim
                        ColorFade on color { duration: Theme.stateMs }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Calendar.snooze(row.uid, row.occurrenceDate, chip.modelData.amount)
                    }
                }
            }
        }

        // Remove only this occurrence of a repeating item.
        HoverButton {
            visible: !row.readOnly
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignVCenter
            icon: "x"
            iconSize: 13
            iconStrokeWidth: 1.8
            textColor: Theme.mute
            hoverTextColor: Theme.fg
            onClicked: Calendar.remove(row.uid, row.recurring ? row.occurrenceDate : undefined)
        }
    }
}
