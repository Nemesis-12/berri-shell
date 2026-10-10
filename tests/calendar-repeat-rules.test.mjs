import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const Format = calendarModule("CalendarFormat.js");
const Items = calendarModule("CalendarItems.js");
const Queries = calendarModule("CalendarQueries.js");
process.env.TZ = "America/Chicago";

// Builds a calendar file with one series for reader, writer and month queries.
function calendar(...lines) {
  return Format.readCalendar(["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:repeat", "SUMMARY:Repeat",
    ...lines, "END:VEVENT", "END:VCALENDAR"].join("\r\n"));
}

// Reads saved text again so tests cover rule preservation as well as expansion.
function saved(doc) {
  return Format.readCalendar(Format.writeCalendar(doc));
}

// Returns start dates through the same month query used by the calendar view.
function monthDates(item, year = 2026, month = 10) {
  return Object.keys(Queries.itemsInMonth([item], year, month)).sort();
}

test("a daily weekday series keeps BYDAY on save and has no weekend days in October", () => {
  const doc = calendar("DTSTART:20261005T090000", "RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR");
  const expected = ["05", "06", "07", "08", "09", "12", "13", "14", "15", "16", "19", "20", "21", "22", "23", "26", "27", "28", "29", "30"].map(day => `2026-10-${day}`);
  for (const read of [doc, saved(doc)]) assert.deepEqual(monthDates(read.items[0]), expected);
  doc.items[0] = Items.applyChanges(doc.items[0], { title: "Edited title" });
  assert.match(Format.writeCalendar(doc), /RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR\r\n/);
  assert.deepEqual(monthDates(saved(doc).items[0]), expected);
});
