import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarCode } from "./fixtures/calendar-code.mjs";

const ics = calendarCode();
const plain = (value) => JSON.parse(JSON.stringify(value));
const fixture = (name) => fs.readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

test("streamed subscription records give the same month as a full parse", () => {
  const text = fixture("bayern.ics");
  const full = ics.readCalendar(text);
  const compact = ics.readCompactCalendar(text);
  assert.equal(compact.records.length, full.items.length);
  assert.equal(compact.records.every((record) => typeof record === "string"), true);
  assert.equal(compact.records.every((record) => record.startsWith("20") && record[10] === "\t"), true);
  const feed = { id: "feed", name: "Feed", kind: "link", color: "blue", hidden: false,
    url: "https://example.test/cal", records: compact.records, colorOverrides: {} };
  const projected = ics.projectStoredCalendars([feed]);
  assert.equal(projected.calendars[0].itemCount, full.items.length);
  const fullItems = ics.mergeCalendars([{ id: "feed", color: "blue", readOnly: true,
    items: full.items }]);
  for (const month of [9, 10, 11]) {
    const expected = ics.itemsInMonth(fullItems, 2026, month, projected.names);
    assert.deepEqual(plain(ics.storedItemsInMonth(projected, 2026, month)), plain(expected));
  }
});

test("calendar order, hidden feeds, own colors, and a repeat survive compact storage", () => {
  const text = ["BEGIN:VCALENDAR", "X-WR-CALNAME:My\\, feed",
    "BEGIN:VEVENT", "UID:same", "DTSTART;VALUE=DATE:20261005", "SUMMARY:Shared", "END:VEVENT",
    "BEGIN:VEVENT", "UID:repeat", "DTSTART;VALUE=DATE:20260930", "RRULE:FREQ=DAILY;COUNT=3",
    "SUMMARY:Repeat", "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
  const compact = ics.readCompactCalendar(text);
  assert.equal(compact.name, "My, feed");
  const local = { id: "berri", name: "berri", kind: "local", color: "accent", hidden: false,
    document: ics.readCalendar(text) };
  const feed = { id: "feed", name: compact.name, kind: "link", color: "blue", hidden: false,
    records: compact.records, colorOverrides: { same: "red" } };
  const month = ics.storedItemsInMonth(ics.projectStoredCalendars([local, feed]), 2026, 10);
  assert.equal(month["2026-10-05"].length, 1);
  assert.equal(month["2026-10-05"][0].calendarId, "feed");
  assert.equal(month["2026-10-05"][0].color, "red");
  assert.deepEqual(plain(month["2026-10-01"].map((item) => item.title)), ["Repeat"]);
  feed.hidden = true;
  const hidden = ics.storedItemsInMonth(ics.projectStoredCalendars([local, feed]), 2026, 10);
  assert.equal(hidden["2026-10-05"][0].calendarId, "berri");
});

test("folded title, alarm, and month span match the editable parser", () => {
  const text = ["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:long",
    "DTSTART;VALUE=DATE:20260930", "DTEND;VALUE=DATE:20261003",
    "SUMMARY:Long calen", " dar item", "BEGIN:VALARM", "TRIGGER:-PT10M",
    "ACTION:DISPLAY", "END:VALARM", "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
  const full = ics.readCalendar(text);
  const compact = ics.readCompactCalendar(text);
  const stored = ics.projectStoredCalendars([{ id: "feed", name: "Feed", kind: "link",
    color: "blue", hidden: false, records: compact.records, colorOverrides: {} }]);
  const items = ics.mergeCalendars([{ id: "feed", color: "blue", readOnly: true,
    items: full.items }]);
  for (const month of [9, 10]) {
    assert.deepEqual(plain(ics.storedItemsInMonth(stored, 2026, month)),
      plain(ics.itemsInMonth(items, 2026, month, stored.names)));
  }
  assert.equal(ics.expandCompactItem(compact.records[0]).title, "Long calendar item");
  assert.equal(ics.expandCompactItem(compact.records[0]).alarmMinutes, 10);
});

test("editable document keeps unknown fields through an edit and save", () => {
  const text = ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:local",
    "DTSTART;TZID=Europe/Berlin:20261005T093000", "SUMMARY:Before", "X-OTHER:keep me",
    "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
  const document = ics.readCalendar(text);
  document.items[0] = ics.applyChanges(document.items[0], { title: "After" });
  const written = ics.writeCalendar(document);
  assert.match(written, /X-OTHER:keep me/);
  assert.match(written, /DTSTART;TZID=Europe\/Berlin:20261005T093000/);
  assert.equal(ics.readCalendar(written).items[0].title, "After");
});
