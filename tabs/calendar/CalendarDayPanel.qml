import QtQuick
import "../../logic/Times.js" as Times
import "../../logic/ShownRows.js" as ShownRows
import qs.common
import qs.services

/**
 * Day panel (mock 5C SPINE, Berri Calendar v2.dc.html): header with the big
 * date number, the NEW and CALS buttons, and the day's list of events,
 * reminders and tasks. New items come only from the form (NEW).
 *
 * The list follows `selectedDate` and live changes of the Calendar store.
 * When the day changes, header and list fade out, swap, and fade in with one
 * value (dayFade). When only the items change, rows fade and slide in or out
 * and the rows below move (ListView transitions).
 */
Item {
    id: root

    /** Day to show (JS Date). */
    property date selectedDate: new Date()

    /** 24-hour clock when true, else "3:00 PM" (mock prop clock24). A settings page sets it. */
    property bool clock24: false

    /** Sent when the user presses NEW. The form opens on it. */
    signal newRequested

    /** True while the tab shows the calendars view. CALS then has the active look. */
    property bool calendarsShown: false

    /** Sent when the user presses CALS. The tab flips the month grid and the calendars view. */
    signal calendarsRequested

    /** Sent when the user clicks a row. The form opens on it. */
    signal itemClicked(string uid, string occurrenceDate)

    /**
     * Drag of a row (the tab draws the ghost). dragStarted carries the item
     * and the row's look; the point arguments are scene positions.
     */
    signal dragStarted(var info)
    signal dragMoved(point scenePoint)
    signal dragFinished(point scenePoint)
    signal dragAborted

    // Day shown in header and list. It follows selectedDate in the middle of the fade.
    property date shownDate: root.selectedDate
    readonly property string shownKey: Times.dayKey(root.shownDate)

    /** 1 = day fully shown, 0 = hidden between two days. */
    property real dayFade: 1

    // Current time as "HH:MM": a reminder that is due gets the accent look.
    readonly property string nowTime: Times.clockOfDate(Clock.minute, true)
    readonly property bool shownIsToday: root.shownKey === Times.dayKey(Clock.minute)

    // A hidden panel keeps its last items and asks the store again when it is shown.
    readonly property var lastItems: ({ list: [] })
    readonly property var items: {
        void Calendar.revision;
        if (!root.visible) return root.lastItems.list;
        root.lastItems.list = Calendar.itemsOn(root.shownDate);
        return root.lastItems.list;
    }

    property bool resetting: false

    // Name of a calendar for the meta line of a read-only row ("" when unknown).
    function calendarName(calendarId) {
        var list = Calendar.calendars || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === calendarId) return list[i].name;
        }
        return "";
    }

    function rowOf(item) {
        return {
            key: item.uid + "|" + item.occurrenceDate,
            uid: item.uid,
            kind: item.kind,
            title: item.title,
            tintKey: item.color || "accent",
            occurrenceDate: item.occurrenceDate,
            time: item.time || "",
            end: item.end || "",
            recurring: !!item.recurring,
            repeat: item.repeat || "none",
            done: !!item.done,
            readOnly: !!item.readOnly,
            calendarName: [root.calendarName(item.calendarId)].concat(item.alsoIn || []).join(" + ")
        };
    }

    // Fills the list from scratch, without row animations.
    function resetRows() {
        rows.clear();
        for (var i = 0; i < root.items.length; i++) rows.append(root.rowOf(root.items[i]));
    }

    // Brings the list in line with the store: removes gone rows, updates kept rows, moves and inserts the rest.
    function syncRows() {
        var wanted = root.items.map(root.rowOf);
        ShownRows.matchRows(rows, wanted, "key");
    }

    onItemsChanged: {
        if (!root.resetting) root.syncRows();
    }

    Component.onCompleted: root.resetRows()

    property string lastKey: Times.dayKey(root.selectedDate)

    onSelectedDateChanged: {
        var key = Times.dayKey(root.selectedDate);
        if (key === root.lastKey) return;
        root.lastKey = key;
        dayChange.restart();
    }

    SequentialAnimation {
        id: dayChange

        StandardMotion {
            target: root
            property: "dayFade"
            to: 0
            duration: 100
        }
        ScriptAction {
            script: {
                root.resetting = true;
                root.shownDate = root.selectedDate;
                root.resetRows();
                root.resetting = false;
            }
        }
        StandardMotion {
            target: root
            property: "dayFade"
            to: 1
            duration: Theme.hoverMs
        }
    }

    WhileVisible { service: Clock }

    ListModel {
        id: rows
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.border
    }

    // Header: DAY label, big number, weekday and month line, NEW button.
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 96

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: sideButtons.left
            anchors.rightMargin: 1
            color: Theme.card

            // "DAY" reads bottom to top.
            Item {
                id: dayLabel
                x: 10
                y: 14
                width: 9
                height: parent.height - 28

                MonoText {
                    // Rotated text is centered in the 9px line box, like the mock's vertical text.
                    x: Math.round((dayLabel.width - implicitHeight) / 2 * 2) / 2
                    y: dayLabel.height
                    rotation: -90
                    transformOrigin: Item.TopLeft
                    text: "DAY"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: 1.62
                    color: Theme.dim
                }
            }

            Row {
                id: headerContent
                x: 10 + 9 + 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                spacing: 10
                opacity: root.dayFade

                // Line height .78 of 68px.
                Item {
                    width: numberText.implicitWidth
                    height: 53

                    Text {
                        textFormat: Text.PlainText
                        id: numberText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.shownDate.getDate()
                        font.family: Theme.condensed
                        font.pixelSize: 68
                        font.weight: Font.Medium
                        font.letterSpacing: -2.04
                        color: Theme.fg
                    }
                }

                Column {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    spacing: 6

                    Item {
                        width: weekdayText.implicitWidth
                        height: 10

                        MonoText {
                            id: weekdayText
                            anchors.verticalCenter: parent.verticalCenter
                            text: Times.weekdaysLong[root.shownDate.getDay()].toUpperCase()
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            font.letterSpacing: 1.4
                            color: Theme.fg
                        }
                    }

                    Item {
                        width: countText.implicitWidth
                        height: 9

                        MonoText {
                            id: countText
                            anchors.verticalCenter: parent.verticalCenter
                            text: Times.monthsShort[root.shownDate.getMonth()] + " " + root.shownDate.getFullYear()
                                + " · " + (rows.count === 0 ? "free" : rows.count + (rows.count === 1 ? " item" : " items"))
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            font.letterSpacing: 0.72
                            color: Theme.dim
                        }
                    }
                }
            }
        }

        // Right-hand column: NEW (accent) above CALS (neutral), each half the header height.
        Item {
            id: sideButtons
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 64

            Rectangle {
                id: newButton
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: (parent.height - 1) / 2
                color: newMouse.containsMouse ? Theme.accentLight : Theme.accent

                ColorFade on color {}

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "plus"
                        size: 16
                        strokeWidth: 2
                        color: Theme.onAccent
                    }

                    MonoText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "NEW"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.26
                        color: Theme.onAccent
                    }
                }

                MouseArea {
                    id: newMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.newRequested()
                }
            }

            // CALS: raised while the month grid shows; soft accent fill and a 2px accent bar on the left edge while the calendars view shows.
            Rectangle {
                id: calsButton
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: (parent.height - 1) / 2
                color: root.calendarsShown ? Theme.selectionSoft : Theme.raised

                ColorFade on color { duration: Theme.stateMs }

                Rectangle {
                    width: 2
                    height: parent.height
                    color: Theme.accent
                    opacity: root.calendarsShown ? 1 : 0

                    Fade on opacity { duration: Theme.stateMs }
                }

                // Hover brightening (mock: brightness 1.2).
                Rectangle {
                    anchors.fill: parent
                    color: Theme.fg
                    opacity: calsMouse.containsMouse ? 0.06 : 0

                    Fade on opacity {}
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "layers-2"
                        size: 16
                        strokeWidth: 2
                        color: calsLabel.color
                    }

                    MonoText {
                        id: calsLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "CALS"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.26
                        color: root.calendarsShown ? Theme.accentLight : Theme.dim

                        ColorFade on color { duration: Theme.stateMs }
                    }
                }

                MouseArea {
                    id: calsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.calendarsRequested()
                }
            }
        }
    }

    // The list.
    Rectangle {
        id: listCard
        anchors.top: header.bottom
        anchors.topMargin: 1
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        color: Theme.card

        AnimatedList {
            id: list
            anchors.fill: parent
            clip: true
            model: rows
            boundsBehavior: Flickable.StopAtBounds
            opacity: root.dayFade
            transform: Translate { y: 8 * (1 - root.dayFade) }

            animateChanges: root.dayFade > 0.5

            delegate: DayItemRow {
                shownKey: root.shownKey
                shownIsToday: root.shownIsToday
                nowTime: root.nowTime
                clock24: root.clock24
                onItemClicked: (uid, occurrenceDate) => root.itemClicked(uid, occurrenceDate)
                onDragStarted: info => root.dragStarted(info)
                onDragMoved: scenePoint => root.dragMoved(scenePoint)
                onDragFinished: scenePoint => root.dragFinished(scenePoint)
                onDragAborted: root.dragAborted()
            }
        }

        // Empty day. Lines are 16px high (CSS 10px x 1.6); the extra 1px centers the glyphs in the line like a browser does.
        MonoText {
            x: 12
            y: 15
            width: parent.width - 24
            wrapMode: Text.WordWrap
            text: "NOTHING ON THIS DAY. USE + NEW."
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: 0.4
            lineHeight: 16
            lineHeightMode: Text.FixedHeight
            color: Theme.dim
            opacity: rows.count === 0 ? root.dayFade : 0

            Behavior on opacity {
                StandardMotion { duration: Theme.hoverMs }
            }
        }
    }
}
