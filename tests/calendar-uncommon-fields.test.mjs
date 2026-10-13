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
