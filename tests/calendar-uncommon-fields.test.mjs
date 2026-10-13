import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarModule } from "./fixtures/calendar-code.mjs";

process.env.TZ = "UTC";
const Format = calendarModule("CalendarFormat.js");
const Items = calendarModule("CalendarItems.js");
const Queries = calendarModule("CalendarQueries.js");

// Reads one event through the editable calendar interface.
function calendar(...lines) {
  return Format.readCalendar(["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:x",
    "SUMMARY:Original", ...lines, "END:VEVENT", "END:VCALENDAR"].join("\r\n"));
}

// Saves through the real writer and reads its output again.
function saved(document) {
  return Format.readCalendar(Format.writeCalendar(document));
}

test("DURATION keeps the event span through an unrelated edit and save", () => {
  const document = Format.readCalendar(fs.readFileSync(new URL("./fixtures/feeds/duration.ics", import.meta.url), "utf8"));
  document.items[0] = Items.applyChanges(document.items[0], { title: "Edited" });
  const text = Format.writeCalendar(document);
  assert.doesNotMatch(text, /DTEND/);
  assert.match(text, /DURATION:P3D/);
  for (const read of [document, saved(document)]) {
    const byUid = Object.fromEntries(read.items.map(item => [item.uid, item]));
    assert.equal(byUid.days.endDate, "2026-10-10");
    assert.deepEqual(Object.keys(Queries.itemsInMonth([byUid.days], 2026, 10)).sort(),
      ["2026-10-08", "2026-10-09", "2026-10-10"]);
    assert.equal(byUid.clock.endDate, "2026-10-09");
    assert.equal(byUid.clock.end, "00:31");
    assert.equal(byUid["dst-day"].end, "08:00");
    assert.equal(byUid["dst-hours"].end, "07:00");
  }
});

test("editing a duration end writes DTEND alone and keeps an unchanged end second", () => {
  const document = calendar("DTSTART:20261008T230030", "DURATION:PT45S");
  document.items[0] = Items.applyChanges(document.items[0], { time: "22:00" });
  const text = Format.writeCalendar(document);
  assert.doesNotMatch(text, /DURATION/);
  assert.match(text, /DTEND:20261008T230115/);
  assert.equal(saved(document).items[0].end, "23:01");
  document.items[0] = Items.applyChanges(document.items[0], { end: "23:30" });
  assert.match(Format.writeCalendar(document), /DTEND:20261008T233000/);
  assert.equal(saved(document).items[0].end, "23:30");
});

test("an unsupported DURATION stays raw without a generated DTEND", () => {
  const document = calendar("DTSTART;VALUE=DATE:20261008", "DURATION:P1Y");
  const text = Format.writeCalendar(document);
  assert.match(text, /DURATION:P1Y/);
  assert.doesNotMatch(text, /DTEND/);
  assert.equal(saved(document).items[0].raw[0], "DURATION:P1Y");
});

test("alarm seconds survive edits, saving, compact expansion and the delivery scan", () => {
  const document = Format.readCalendar(fs.readFileSync(new URL("./fixtures/feeds/alarm-seconds.ics", import.meta.url), "utf8"));
  document.items[0] = Items.applyChanges(document.items[0], { title: "Edited" });
  const text = Format.writeCalendar(document);
  assert.match(text, /TRIGGER:-PT90S/);
  assert.match(text, /TRIGGER:-PT1S/);
  assert.match(text, /TRIGGER:PT30S/);
  for (const read of [document, saved(document)]) {
    assert.equal(read.items[0].alarmMinutes, 1.5);
    assert.equal(Format.expandCompactItem(read.items[1]).alarmMinutes, 1 / 60);
    assert.equal(read.items[2].alarmMinutes, null);
    const due = Items.dueBetween(read.items, Date.UTC(2026, 9, 8, 8, 58, 59), Date.UTC(2026, 9, 8, 8, 59));
    assert.equal(due[0].dueMs, Date.UTC(2026, 9, 8, 8, 59));
  }
});

test("unknown zones keep edited source clocks, carry a note and never gain UTC", () => {
  for (const zone of ["UTC", "America/Chicago"]) {
    process.env.TZ = zone;
    const document = calendar("DTSTART;TZID=W. Europe Standard Time:20261005T093027",
      "DTEND;TZID=W. Europe Standard Time:20261005T103027", "RRULE:FREQ=DAILY");
    document.items[0] = Items.applyChanges(document.items[0], { time: "10:00", end: "11:00", exdates: ["2026-10-06"] });
    const text = Format.writeCalendar(document);
    assert.match(text, /DTSTART;TZID=W\. Europe Standard Time:20261005T100000/);
    assert.match(text, /DTEND;TZID=W\. Europe Standard Time:20261005T110000/);
    assert.match(text, /EXDATE;TZID=W\. Europe Standard Time:20261006T100000/);
    for (const read of [document, saved(document)]) {
      assert.equal(read.items[0].sourceDates.start.instantMs, null);
      assert.deepEqual(Array.from(read.items[0].unknownZones), ["W. Europe Standard Time"]);
      const projection = Queries.projectStoredCalendars([{ id: "file", kind: "file", document: read }]);
      assert.equal(projection.calendars[0].note, "Unknown time zone: W. Europe Standard Time. Source clocks are shown");
    }
  }
  process.env.TZ = "UTC";
});

test("an edited repeat end refuses UTC conversion when its start zone is unknown", () => {
  const document = calendar("DTSTART;TZID=Unknown/Zone:20261005T093000", "RRULE:FREQ=DAILY;UNTIL=20261006T093000Z");
  document.items[0] = Items.applyChanges(document.items[0], { until: "2026-10-07" });
  assert.throws(() => Format.writeCalendar(document), /Cannot convert repeat end in an unknown time zone/);
  const known = calendar("DTSTART;TZID=Europe/Berlin:20261005T093000", "RRULE:FREQ=DAILY;UNTIL=20261006T093000Z");
  known.items[0] = Items.applyChanges(known.items[0], { until: "2026-10-07" });
  assert.equal(saved(known).items[0].until, "2026-10-07");
});

test("a non-ASCII BYDAY reports its error, keeps source text and reads the other events", () => {
  const document = Format.readCalendar(fs.readFileSync(new URL("./fixtures/feeds/non-ascii-byday.ics", import.meta.url), "utf8"));
  document.items[0] = Items.applyChanges(document.items[0], { title: "Edited" });
  assert.match(Format.writeCalendar(document), /RRULE:FREQ=MONTHLY;BYDAY=éA/);
  for (const read of [document, saved(document)]) {
    assert.deepEqual(Array.from(read.errors), ["bad-day: non-ASCII BYDAY value: éA"]);
    assert.deepEqual(Array.from(read.items, item => [item.uid, item.repeat]),
      [["good-before", "daily"], ["bad-day", "none"], ["good-after", "weekly"]]);
  }
});
