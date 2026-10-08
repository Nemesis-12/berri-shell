import QtQuick

/**
 * One of the two month pages of CalendarTab. The tab shows one page in front
 * and slides it against the other when the month changes. The page passes
 * the seven grid events to the tab once, here, so a change reaches both pages.
 *
 * Use two of them: `front` is true for the page that shows the current month.
 * `tab` is the CalendarTab, which owns the month change `progress`.
 */
CalendarMonthGrid {
    id: root

    /** The CalendarTab that owns this page. */
    required property var tab

    /** True while this page is the one in front. */
    required property bool front

    anchors.fill: parent
    year: new Date().getFullYear()
    month: new Date().getMonth()
    weekStart: tab.weekStart
    selectedDate: tab.selectedDate
    today: tab.today
    opacity: front ? tab.progress : 1 - tab.progress
    visible: opacity > 0.001
    transform: Translate { y: 10 * root.tab.slideSign * (root.front ? 1 - root.tab.progress : -root.tab.progress) }
    z: front ? 1 : 0
    enabled: front
    dropKey: front ? tab.overKey : ""

    onDayPicked: day => tab.pick(day)
    onDayAddRequested: day => tab.addOn(day)
    onItemPicked: (day, uid, occurrenceDate) => tab.openItem(day, uid, occurrenceDate)
    onDragStarted: info => tab.beginDrag(info)
    onDragMoved: scenePoint => tab.moveDrag(scenePoint)
    onDragFinished: scenePoint => tab.endDrag(scenePoint)
    onDragAborted: tab.abortDrag()
}
