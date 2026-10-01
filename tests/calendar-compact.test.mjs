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
  assert.equal(compact.records.every((record) => record && typeof record === "object"), true);
  assert.equal(compact.records.every((record) => typeof record.uid === "string" && typeof record.date === "string"), true);
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

test("a last repeating multi-day occurrence remains visible in the next month", () => {
  const text = ["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:trip",
    "DTSTART;VALUE=DATE:20260929", "DTEND;VALUE=DATE:20261003",
    "RRULE:FREQ=DAILY;UNTIL=20260930", "SUMMARY:Trip", "END:VEVENT",
    "END:VCALENDAR", ""].join("\r\n");
  const records = ics.readCompactCalendar(text).records;
  const stored = ics.projectStoredCalendars([{ id: "feed", name: "Feed", kind: "link",
    color: "blue", hidden: false, records, colorOverrides: {} }]);
  const month = ics.storedItemsInMonth(stored, 2026, 10);
  assert.deepEqual(plain(month["2026-10-01"].map((entry) => entry.occurrenceDate)),
    ["2026-09-29", "2026-09-30"]);
});

test("subscription files keep a watcher without keeping their text loaded", () => {
  const source = fs.readFileSync(new URL("../services/CalendarFiles.qml", import.meta.url), "utf8");
  assert.match(source, /delegate:\s*FileView\s*\{[\s\S]*watchChanges:\s*true/);
  assert.match(source, /preload:\s*!isLink/);
  assert.match(source, /onFileChanged:\s*\{\s*if \(isLink\) readLink\(\)/);
  assert.match(source, /function readLink\(\)[\s\S]*readNow\(filePath\)/);
});

test("compact records keep location and sort events by start time", () => {
  const text = ["BEGIN:VCALENDAR",
    "BEGIN:VEVENT", "UID:late", "DTSTART:20261005T150000", "SUMMARY:Late",
    "LOCATION:Room\\, two", "END:VEVENT",
    "BEGIN:VEVENT", "UID:early", "DTSTART:20261005T090000", "SUMMARY:Early",
    "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
  const records = ics.readCompactCalendar(text).records;
  assert.deepEqual(plain(records.map((record) => record.uid)), ["early", "late"]);
  assert.equal(records[1].location, "Room, two");
  assert.equal(ics.expandCompactItem(records[1]).location, "Room, two");
  assert.equal(records[0].date, "2026-10-05");
});

test("link check counts duplicate records without building feed items", () => {
  const existing = [{ id: "local", document: { items: [
    { uid: "same", date: "2026-10-05", time: "09:00", title: "Meeting", repeat: "none", interval: 1 },
  ] } }, { id: "feed", records: [{ uid: "new", date: "2026-10-07", time: "09:00",
    title: "New", repeat: "none", interval: 1 }] }];
  const records = ics.readCompactCalendar(["BEGIN:VCALENDAR",
    "BEGIN:VEVENT", "UID:same", "DTSTART:20261006T100000", "SUMMARY:Other", "END:VEVENT",
    "BEGIN:VEVENT", "UID:different", "DTSTART:20261005T090000", "SUMMARY:Meeting", "END:VEVENT",
    "BEGIN:VEVENT", "UID:new", "DTSTART:20261007T090000", "SUMMARY:New", "END:VEVENT",
    "END:VCALENDAR", ""].join("\r\n")).records;
  assert.equal(ics.countStoredDuplicates(records, existing), 3);
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
