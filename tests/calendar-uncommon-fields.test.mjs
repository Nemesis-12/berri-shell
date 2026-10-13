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
