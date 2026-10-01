pragma Singleton
import QtQuick
import Quickshell
import qs.common

/**
 * The one minute clock. `minute` is a Date that changes once per minute, right
 * after the minute boundary, so every view shows the same time. Bind to it:
 * `text: Times.clockOfDate(Clock.minute, true)`.
 * It ticks only while a view is visible (`viewers` > 0, see WhileVisible.qml).
 * When the first viewer appears, `minute` is set to the current time at once.
 */
Singleton {
    id: root

    /** How many views are visible now (see WhileVisible.qml). */
    property int viewers: 0

    property date minute: new Date()

    onViewersChanged: {
        if (viewers !== 1) return;
        minute = new Date();
        minuteTimer.interval = untilNextMinute();
    }

    Timer {
        id: minuteTimer
        repeat: true
        running: root.viewers > 0
        interval: root.untilNextMinute()
        onTriggered: {
            root.minute = new Date();
            interval = root.untilNextMinute();
        }
    }

    // A few ms past the boundary, so a timer that fires early still reads the new minute.
    function untilNextMinute(): int {
        var d = new Date();
        return 60000 - (d.getSeconds() * 1000 + d.getMilliseconds()) + 20;
    }
}
