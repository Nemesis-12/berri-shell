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

test("daily INTERVAL selects days before BYDAY and COUNT counts only selected days", () => {
  const doc = calendar("DTSTART:20261005T090000", "RRULE:FREQ=DAILY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=4");
  const expected = ["2026-10-05", "2026-10-07", "2026-10-09", "2026-10-19"];
  for (const read of [doc, saved(doc)]) assert.deepEqual(monthDates(read.items[0]), expected);
});

test("monthly BYDAY lists select every matching weekday and survive save and edits", () => {
  const doc = calendar("DTSTART:20261005T090000", "RRULE:FREQ=MONTHLY;BYDAY=MO,WE;COUNT=7");
  const expected = ["2026-10-05", "2026-10-07", "2026-10-12", "2026-10-14", "2026-10-19", "2026-10-21", "2026-10-26"];
  for (const read of [doc, saved(doc)]) assert.deepEqual(monthDates(read.items[0]), expected);
  doc.items[0] = Items.applyChanges(doc.items[0], { title: "Edited" });
  assert.match(Format.writeCalendar(doc), /BYDAY=MO,WE/);
  assert.deepEqual(monthDates(saved(doc).items[0]), expected);
});

test("UTC weekly repeats keep their instant across local DST and a save", () => {
  const doc = calendar("DTSTART:20261026T140000Z", "DTEND:20261026T150000Z", "RRULE:FREQ=WEEKLY;COUNT=2");
  for (const read of [doc, saved(doc)]) {
    const days = Queries.itemsInMonth(read.items, 2026, 11);
    assert.deepEqual(Array.from(days["2026-11-02"], o => [o.time, o.end]), [["08:00", "09:00"]]);
  }
  assert.match(Format.writeCalendar(doc), /DTSTART:20261026T140000Z/);
});

for (const [name, start, before, equal] of [
  ["floating", "DTSTART:20261008T090000", "20261009T085959", "20261009T090000"],
  ["UTC", "DTSTART:20261008T140000Z", "20261009T135959Z", "20261009T140000Z"],
  ["Berlin", "DTSTART;TZID=Europe/Berlin:20261008T090000", "20261009T065959Z", "20261009T070000Z"],
]) {
  test(`${name} UNTIL excludes later instants and includes its exact bound after saving`, () => {
    for (const [until, expected] of [[before, ["2026-10-08"]], [equal, ["2026-10-08", "2026-10-09"]]]) {
      const doc = calendar(start, `RRULE:FREQ=DAILY;UNTIL=${until}`);
      for (const read of [doc, saved(doc)]) assert.deepEqual(monthDates(read.items[0]), expected);
      assert.match(Format.writeCalendar(doc), new RegExp(`UNTIL=${until}`));
    }
  });
}

test("changing a zoned UNTIL day writes the end of that day in the source zone", () => {
  const doc = calendar("DTSTART;TZID=Europe/Berlin:20261008T090000", "RRULE:FREQ=DAILY;UNTIL=20261009T215959Z");
  doc.items[0] = Items.applyChanges(doc.items[0], { until: "2026-10-10" });
  const text = Format.writeCalendar(doc);
  assert.match(text, /UNTIL=20261010T215959Z/);
  assert.deepEqual(monthDates(saved(doc).items[0]), ["2026-10-08", "2026-10-09", "2026-10-10"]);
});

for (const [name, start, exclusion, edited, expected] of [
  ["floating", "DTSTART:20261008T090000", "EXDATE:20261009T090000", "10:00", "EXDATE:20261009T100000"],
  ["UTC", "DTSTART:20261008T140000Z", "EXDATE:20261009T140000Z", "10:00", "EXDATE:20261009T150000Z"],
  ["Berlin", "DTSTART;TZID=Europe/Berlin:20261008T090000", "EXDATE;TZID=Europe/Berlin:20261009T090000", "03:00", "EXDATE;TZID=Europe/Berlin:20261009T100000"],
]) {
  test(`${name} EXDATE follows a series time edit and survives read-save-read`, () => {
    const doc = calendar(start, "RRULE:FREQ=DAILY;COUNT=3", exclusion);
    assert.ok(Format.writeCalendar(doc).includes(exclusion));
    doc.items[0] = Items.applyChanges(doc.items[0], { time: edited });
    const text = Format.writeCalendar(doc);
    assert.ok(text.includes(expected), text);
    assert.deepEqual(monthDates(Format.readCalendar(text).items[0]), ["2026-10-08", "2026-10-10"]);
  });
}

test("an edited UTC series writes an excluded winter occurrence at its UTC clock", () => {
  const doc = calendar("DTSTART:20261026T140000Z", "RRULE:FREQ=WEEKLY;COUNT=3", "EXDATE:20261102T140000Z");
  doc.items[0] = Items.applyChanges(doc.items[0], { time: "10:00" });
  assert.match(Format.writeCalendar(doc), /EXDATE:20261102T150000Z/);
  assert.deepEqual(monthDates(saved(doc).items[0], 2026, 11), ["2026-11-09"]);
});

test("unsupported RDATE and EXRULE keep their raw lines and use the calendar source note", () => {
  const extra = "RDATE;TZID=Europe/Berlin:20261012T090000,20261013T090000";
  const exclusion = "EXRULE:FREQ=WEEKLY;BYDAY=MO";
  const doc = calendar("DTSTART:20261008T090000", "RRULE:FREQ=DAILY;COUNT=3", extra, exclusion);
  doc.items[0] = Items.applyChanges(doc.items[0], { title: "Edited" });
  const text = Format.writeCalendar(doc);
  assert.ok(text.includes(extra));
  assert.ok(text.includes(exclusion));
  for (const read of [doc, Format.readCalendar(text)]) {
    const source = { id: "repeat", name: "Repeat", kind: "file", document: read };
    const rows = Queries.projectStoredCalendars([source]).calendars;
    assert.equal(rows[0].error, "RDATE and EXRULE are not supported");
    assert.equal(Queries.projectStoredCalendars([{ ...source, error: "Cannot read file" }]).calendars[0].error, "Cannot read file");
  }
});

for (const [name, start, before, equal] of [
  ["floating", "DTSTART:20261008T090030", "20261009T090015", "20261009T090030"],
  ["UTC", "DTSTART:20261008T140030Z", "20261009T140015Z", "20261009T140030Z"],
  ["Berlin", "DTSTART;TZID=Europe/Berlin:20261008T090030", "20261009T070015Z", "20261009T070030Z"],
]) {
  test(`${name} UNTIL uses the original start seconds at the final bound`, () => {
    for (const [until, expected] of [[before, ["2026-10-08"]], [equal, ["2026-10-08", "2026-10-09"]]]) {
      const doc = calendar(start, `RRULE:FREQ=DAILY;UNTIL=${until}`);
      for (const read of [doc, saved(doc)]) assert.deepEqual(monthDates(read.items[0]), expected);
    }
  });
}
