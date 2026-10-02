import QtQml
import "../../logic/CalendarFormat.js" as Format

// Checks the Qt zone reader used by Calendar.qml, without loading the shell.
QtObject {
    function localZone(value, zone) {
        return Date.fromLocaleString(Qt.locale("C"), value + " " + zone, "yyyyMMdd'T'HHmmss tttt").getTime();
    }

    Component.onCompleted: {
        try {
            const expected = Date.UTC(2026, 9, 5, 7, 30, 27);
            const actual = localZone("20261005T093027", "Europe/Berlin");
            if (actual !== expected) throw new Error("Wrong zone instant: " + actual);
            const text = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:zone-check\nDTSTART;TZID=Europe/Berlin:20261005T093027\nEND:VEVENT\nEND:VCALENDAR\n";
            const calendar = Format.readCalendar(text, localZone);
            if (calendar.items[0].sourceDates.start.instantMs !== expected) throw new Error("Wrong parsed instant");
            const output = Format.writeCalendar(calendar, localZone);
            if (output.indexOf("DTSTART;TZID=Europe/Berlin:20261005T093027") < 0) throw new Error("Lost source zone");
            const clock = Format.zoneClock(expected, "Europe/Berlin", localZone);
            if (clock !== "20261005T093027") throw new Error("Wrong zone clock: " + clock);
            console.log("Calendar zone reader passed");
            Qt.exit(0);
        } catch (error) {
            console.error(error);
            Qt.exit(1);
        }
    }
}
