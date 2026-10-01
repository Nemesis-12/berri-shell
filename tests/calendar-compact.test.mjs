import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarCode } from "./fixtures/calendar-code.mjs";

const ics = calendarCode();
const plain = (value) => JSON.parse(JSON.stringify(value));
// One stored subscription record with the fields the Rust parser writes.
const record = (fields) => ({ uid: "", kind: "event", title: "", location: "", date: null, time: null,
  end: null, endDate: null, color: "accent", repeat: "none", interval: 1, byDay: null, until: null,
  count: null, exdates: null, doneDates: null, alarmMinutes: null, status: null, ...fields });

test("calendar order, hidden feeds, own colors, and a repeat survive compact storage", () => {
  const text = ["BEGIN:VCALENDAR", "X-WR-CALNAME:My\\, feed",
    "BEGIN:VEVENT", "UID:same", "DTSTART;VALUE=DATE:20261005", "SUMMARY:Shared", "END:VEVENT",
    "BEGIN:VEVENT", "UID:repeat", "DTSTART;VALUE=DATE:20260930", "RRULE:FREQ=DAILY;COUNT=3",
    "SUMMARY:Repeat", "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
  const compact = { name: "My, feed", records: [
    record({ uid: "same", title: "Shared", date: "2026-10-05" }),
    record({ uid: "repeat", title: "Repeat", date: "2026-09-30", repeat: "daily", count: 3 })] };
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

test("a last repeating multi-day occurrence remains visible in the next month", () => {
  const text = ["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:trip",
    "DTSTART;VALUE=DATE:20260929", "DTEND;VALUE=DATE:20261003",
    "RRULE:FREQ=DAILY;UNTIL=20260930", "SUMMARY:Trip", "END:VEVENT",
    "END:VCALENDAR", ""].join("\r\n");
  const records = [record({ uid: "trip", title: "Trip", date: "2026-09-29", endDate: "2026-10-02",
    repeat: "daily", until: "2026-09-30" })];
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

test("link check counts duplicate records without building feed items", () => {
  const existing = [{ id: "local", document: { items: [
    { uid: "same", date: "2026-10-05", time: "09:00", title: "Meeting", repeat: "none", interval: 1 },
  ] } }, { id: "feed", records: [{ uid: "new", date: "2026-10-07", time: "09:00",
    title: "New", repeat: "none", interval: 1 }] }];
  const records = [
    record({ uid: "same", title: "Other", date: "2026-10-06", time: "10:00" }),
    record({ uid: "different", title: "Meeting", date: "2026-10-05", time: "09:00" }),
    record({ uid: "new", title: "New", date: "2026-10-07", time: "09:00" })];
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
