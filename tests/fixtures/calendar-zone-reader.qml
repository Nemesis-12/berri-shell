import QtTest
import "../../logic/CalendarFormat.js" as Format
import "../../logic/IcsZones.js" as Zones
import "../../logic/CalendarZone.js" as Zone

// Checks production zone conversion and calendar text without loading the shell.
TestCase {
    name: "CalendarZone"

    // The expected instants cover both sides of the spring clock change.
    function test_zone_instant_data() {
        return [
            { tag: "summer", value: "20261005T093027", expected: Date.UTC(2026, 9, 5, 7, 30, 27) },
            { tag: "winter", value: "20260105T093027", expected: Date.UTC(2026, 0, 5, 8, 30, 27) },
            { tag: "before-clock-change", value: "20260329T013027", expected: Date.UTC(2026, 2, 29, 0, 30, 27) },
            { tag: "after-clock-change", value: "20260329T033027", expected: Date.UTC(2026, 2, 29, 1, 30, 27) }
        ];
    }

    function test_zone_instant(data) {
        compare(Zone.instant(data.value, "Europe/Berlin"), data.expected);
    }

    // A local display clock must not replace the source zone when saving.
    function test_calendar_round_trip() {
        const expected = Date.UTC(2026, 9, 5, 7, 30, 27);
        const text = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:zone-check\nDTSTART;TZID=Europe/Berlin:20261005T093027\nEND:VEVENT\nEND:VCALENDAR\n";
        const calendar = Format.readCalendar(text, Zone.instant);
        compare(calendar.items[0].sourceDates.start.instantMs, expected);
        compare(calendar.items[0].time, "02:30");
        const output = Format.writeCalendar(calendar, Zone.instant);
        verify(output.indexOf("DTSTART;TZID=Europe/Berlin:20261005T093027") >= 0);
        compare(Zones.zoneClock(expected, "Europe/Berlin", Zone.instant), "20261005T093027");
        compare(Format.readCalendar(output, Zone.instant).items[0].sourceDates.start.instantMs, expected);
    }
}
