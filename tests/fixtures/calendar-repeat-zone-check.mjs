import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./calendar-code.mjs";

const Format = calendarModule("CalendarFormat.js");
const Items = calendarModule("CalendarItems.js");
const Queries = calendarModule("CalendarQueries.js");

// Reads one series using the child process's display zone.
function calendar(start, rule) {
  return Format.readCalendar(["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:until", "SUMMARY:Repeat",
    start, `RRULE:${rule}`, "END:VEVENT", "END:VCALENDAR"].join("\r\n"));
}

for (const [name, start, until] of [
  ["floating", "DTSTART:20261005T090000", "20261103T090000"],
  ["UTC", "DTSTART:20261005T090000Z", "20261103T090000Z"],
  ["Tokyo", "DTSTART;TZID=Asia/Tokyo:20261005T090000", "20261103T000000Z"],
  ["Berlin", "DTSTART;TZID=Europe/Berlin:20261005T090000", "20261103T080000Z"],
]) {
  test(`${name} edited UNTIL means the end of the chosen display day`, () => {
    const doc = calendar(start, `FREQ=DAILY;UNTIL=${until}`);
    assert.ok(Format.writeCalendar(doc).replace(/\r\n[ \t]/g, "").includes(`UNTIL=${until}`));
    doc.items[0] = Items.applyChanges(doc.items[0], { until: "2026-11-10" });
    const reread = Format.readCalendar(Format.writeCalendar(doc));
    assert.equal(reread.items[0].until, "2026-11-10");
    assert.equal(reread.items[0].untilMs, new Date(2026, 10, 10, 23, 59, 59).getTime());
    const dates = Object.keys(Queries.itemsInMonth(reread.items, 2026, 11)).sort();
    assert.deepEqual(dates, ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10"].map(day => `2026-11-${day}`));
  });
}

test("an all-day UNTIL stays a date after an edit", () => {
  const doc = calendar("DTSTART;VALUE=DATE:20261005", "FREQ=WEEKLY;UNTIL=20261103");
  doc.items[0] = Items.applyChanges(doc.items[0], { until: "2026-11-10" });
  assert.match(Format.writeCalendar(doc), /UNTIL=20261110\r\n/);
  assert.equal(Format.readCalendar(Format.writeCalendar(doc)).items[0].until, "2026-11-10");
});
