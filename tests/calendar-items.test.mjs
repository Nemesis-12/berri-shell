import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const Format = calendarModule("CalendarFormat.js");
const Items = calendarModule("CalendarItems.js");
const Queries = calendarModule("CalendarQueries.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// ---- identity

test("an item key round trips and malformed keys name no item", () => {
  assert.deepEqual(plain(Items.itemIdentity(Items.itemKey("work", "a|b@x"))), { calendarId: "work", uid: "a|b@x" });
  for (const bad of [undefined, null, 5, "", "not json", "[]", '["a"]', '["a","b","c"]', '[1,"b"]', '{"calendarId":"a","uid":"b"}'])
    assert.equal(Items.itemIdentity(bad), null, String(bad));
});

test("an item lookup finds the uid in the named calendar and skips malformed rows", () => {
  const rows = [null, {}, { uid: 7 }, { uid: "x" }];
  assert.equal(Items.itemIndex(rows, Items.itemKey("b", "x"), "b"), 3);
  assert.equal(Items.itemIndex(rows, Items.itemKey("a", "x"), "b"), -1);
  assert.equal(Items.itemIndex(rows, Items.itemKey("b", "y"), "b"), -1);
  assert.equal(Items.itemIndex(rows, "garbage", "b"), -1);
});

// ---- stored items

test("a stored item keeps good fields exactly", () => {
  const fields = { uid: "u1", kind: "task", title: "Pay", date: "2026-10-05", time: "09:30", end: "10:00", endDate: null,
    color: "#ff0000", repeat: "weekly", interval: 2, byDay: [1, 3], until: "2026-12-01", count: null,
    exdates: ["2026-10-12"], doneDates: ["2026-10-05"], alarmMinutes: 15, status: "CONFIRMED", stamp: "20261001T000000Z" };
  const item = Items.storedItem(fields);
  for (const key of Object.keys(fields)) assert.deepEqual(plain(item[key]), fields[key], key);
});

test("a stored item replaces each malformed field with its default", () => {
  const item = Items.storedItem({ uid: 5, kind: "meeting", title: null, date: "tomorrow", time: "9am", end: 900,
    endDate: "x", color: "bogus", repeat: "hourly", interval: "x", byDay: [1, "x", 9, 6], until: 3, count: -2,
    exdates: ["2026-10-01", "nope", 4], doneDates: "2026-10-01", alarmMinutes: -5, status: 7, raw: "x",
    monthWeekday: { nth: 0, day: 2 }, zoned: { date: "x" }, changedOccurrences: [{ from: "2026-10-01" }, 5] });
  assert.deepEqual(plain({ ...item, stamp: null }), { uid: "", kind: "event", title: "",
    date: null, time: null, end: null, endDate: null, color: "accent", repeat: "none", interval: 1, byDay: [],
    monthWeekday: null, until: null, count: null, exdates: [], doneDates: [], alarmMinutes: null, status: null, stamp: null,
    ruleRest: null, zoned: null, changedOccurrences: [], raw: [], rawChildren: [] });
  assert.deepEqual(plain(Items.storedItem({ repeat: "weekly", byDay: [1, "x", 9, 6] }).byDay), [1, 6]);
});

test("a stored item from a stored record accepts null lists", () => {
  const item = Items.storedItem({ uid: "r", byDay: null, exdates: null, doneDates: null, location: "Room 4" });
  assert.deepEqual(plain([item.byDay, item.exdates, item.doneDates, item.location]), [[], [], [], "Room 4"]);
});

test("a new item gets its own uid and stamp unless the fields give them", () => {
  const made = Items.makeItem({ date: "2026-10-05" });
  assert.match(made.uid, /@berri-shell$/);
  assert.match(Items.makeItem({ uid: "" }).uid, /@berri-shell$/);
  assert.match(made.stamp, /^\d{8}T\d{6}Z$/);
  assert.equal(Items.makeItem({ uid: "mine", stamp: "20260101T000000Z" }).uid, "mine");
  assert.equal(Items.makeItem({ uid: "mine", stamp: "20260101T000000Z" }).stamp, "20260101T000000Z");
});

test("a link record without a usable uid keeps the same uid on every read", () => {
  const record = { uid: "", title: "Same", date: "2026-10-05", time: "09:00" };
  const first = Format.expandCompactItem(record).uid;
  assert.notEqual(first, "");
  assert.equal(Format.expandCompactItem(record).uid, first);
  assert.equal(Format.expandCompactItem({ ...record, uid: 5 }).uid, first);
  assert.notEqual(Format.expandCompactItem({ ...record, title: "Other" }).uid, first);
  assert.equal(Format.expandCompactItem({ ...record, uid: "kept" }).uid, "kept");
});

test("a link record expands to a stored item with checked fields", () => {
  const item = Format.expandCompactItem({ uid: "r1", kind: "event", title: 12, location: "Hall", date: "2026-10-05",
    time: "25", end: null, endDate: null, color: "accent", repeat: "daily", interval: 0, byDay: null, until: null,
    count: null, exdates: null, doneDates: null, alarmMinutes: null, status: null });
  assert.deepEqual(plain([item.uid, item.title, item.time, item.interval, item.byDay, item.location]),
    ["r1", "", null, 1, [], "Hall"]);
});

// ---- edits

test("an edit keeps the old value of every malformed change and applies the good ones", () => {
  const before = Items.makeItem({ uid: "u", title: "Keep", date: "2026-10-05", time: "09:00", repeat: "daily", interval: 2 });
  const after = Items.applyChanges(before, { title: "New", date: "someday", time: 9, repeat: "hourly", interval: 0,
    kind: "meeting", color: "bogus", byDay: "mon", alarmMinutes: "soon", exdates: [3] });
  assert.deepEqual(plain([after.title, after.date, after.time, after.repeat, after.interval, after.kind, after.color,
    after.byDay, after.alarmMinutes, after.exdates]),
  ["New", "2026-10-05", "09:00", "daily", 2, "event", "accent", [], null, []]);
});

test("an edit cannot change identity fields and does not change its input", () => {
  const before = Items.makeItem({ uid: "u", title: "Keep", date: "2026-10-05" });
  const copy = plain(before);
  const after = Items.applyChanges(before, { uid: "other", calendarId: "b", readOnly: true, sourceUid: "z", title: "Changed" });
  assert.equal(after.uid, "u");
  assert.equal(after.title, "Changed");
  assert.equal("calendarId" in after, false);
  assert.deepEqual(plain(before), copy);
});

// ---- projected and shown items

test("a projected item adds the calendar fields to a copy and leaves the stored item alone", () => {
  const stored = Items.storedItem({ uid: "u", title: "T", date: "2026-10-05", color: "red" });
  const own = Items.projectedItem(stored, "work", false);
  assert.deepEqual(plain([own.calendarId, own.readOnly, own.hasOwnColor, own.color]), ["work", false, true, "red"]);
  const link = Items.projectedItem(stored, "feed", true);
  assert.deepEqual(plain([link.readOnly, link.hasOwnColor]), [true, false]);
  assert.equal("calendarId" in stored, false);
  assert.equal("readOnly" in stored, false);
  assert.equal(Items.projectedItem(stored, 7, false).calendarId, "berri");
});

test("merging calendars leaves the stored items unchanged", () => {
  const stored = Items.storedItem({ uid: "u", title: "T", date: "2026-10-05" });
  const copy = plain(stored);
  const merged = Queries.mergeCalendars([{ id: "work", color: "blue", hidden: false, readOnly: false, items: [stored] }]);
  assert.deepEqual(plain([merged[0].calendarId, merged[0].color]), ["work", "blue"]);
  assert.deepEqual(plain(stored), copy);
});

test("a shown item carries a key that names its calendar and its file UID", () => {
  const occurrence = { uid: "file-uid", calendarId: "work", title: "T" };
  const shown = Items.shownItem(occurrence);
  assert.equal(shown.sourceUid, "file-uid");
  assert.deepEqual(plain(Items.itemIdentity(shown.uid)), { calendarId: "work", uid: "file-uid" });
  assert.equal(occurrence.uid, "file-uid");
  const odd = Items.shownItem({ uid: 12, calendarId: null });
  assert.deepEqual(plain(Items.itemIdentity(odd.uid)), { calendarId: "berri", uid: "" });
});

// ---- duplicates

test("duplicates are found when stored fields were malformed", () => {
  const a = Items.projectedItem(Items.storedItem({ uid: "a", title: "  Team   SYNC ", date: "2026-10-05", time: "10:00" }), "one", false);
  const b = Items.projectedItem(Items.storedItem({ uid: "b", title: "team sync (2-1)", date: "2026-10-05", time: "10:00", interval: "x" }), "two", false);
  const c = Items.projectedItem(Items.storedItem({ uid: "c", title: 5, date: "bad", time: "bad" }), "two", false);
  const shown = Queries.dropDuplicateItems([a, b, c]);
  assert.deepEqual(plain(shown.map((item) => item.uid)), ["a", "c"]);
  assert.deepEqual(plain(shown[0].alsoInIds), ["two"]);
  assert.equal(Queries.countDuplicates([c], [a, b]), 0);
  assert.equal(Queries.countDuplicates([b], [a]), 1);
});

test("duplicate counting reads malformed link records without throwing", () => {
  const records = [{ uid: "x", title: null, date: "2026-10-05", time: undefined, repeat: undefined, interval: null },
    { uid: "y", title: "Same", date: "2026-10-05", time: null, repeat: "none" }];
  const existing = [{ id: "one", records: [{ uid: "y", title: "Same", date: "2026-10-05", time: null, repeat: "none" }] }];
  assert.equal(Queries.countStoredDuplicates(records, existing), 1);
});

// ---- timed events across midnight

const timedFile = (start, end) => ["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:night", "SUMMARY:Night",
  `DTSTART:${start}`, `DTEND:${end}`, "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");

test("a timed event across midnight shows once on each day it overlaps", () => {
  const items = Format.readCalendar(timedFile("20261001T230000", "20261002T010000")).items;
  assert.equal(Queries.itemsOn(items, "2026-10-01").length, 1);
  const second = plain(Queries.itemsOn(items, "2026-10-02"));
  assert.equal(second.length, 1);
  assert.equal(second[0].title, "Night");
  assert.equal(Queries.itemsOn(items, "2026-10-03").length, 0);
});

test("a timed event that ends exactly at midnight does not show on the next day", () => {
  const items = Format.readCalendar(timedFile("20261001T230000", "20261002T000000")).items;
  assert.equal(Queries.itemsOn(items, "2026-10-01").length, 1);
  assert.equal(Queries.itemsOn(items, "2026-10-02").length, 0);
});

test("a repeating timed event across midnight shows its tail on the next day", () => {
  const text = timedFile("20261001T230000", "20261002T010000").replace("END:VEVENT", "RRULE:FREQ=WEEKLY;COUNT=2\r\nEND:VEVENT");
  const items = Format.readCalendar(text).items;
  assert.deepEqual(plain(Queries.itemsOn(items, "2026-10-09").map((o) => o.occurrenceDate)), ["2026-10-08"]);
});

test("duplicate removal sets membership fields on kept input entries in place", () => {
  const first = { uid: "first", calendarId: "a", date: "2026-10-05", repeat: "none", time: "09:00", title: "Meeting" };
  const colored = { ...first, uid: "colored", calendarId: "b", hasOwnColor: true };
  const alone = { ...first, uid: "alone", title: "Lunch", time: "12:00" };
  const beforeFirst = { ...first };
  const input = [first, colored, alone];
  const keptInputs = Queries.dropDuplicateItems(input);
  assert.equal(keptInputs[0], colored);
  assert.equal(keptInputs[1], alone);
  assert.deepEqual(plain(colored.alsoInIds), ["a"]);
  assert.deepEqual(plain(colored.alsoIn), ["a"]);
  assert.deepEqual(plain(alone.alsoInIds), []);
  assert.deepEqual(plain(alone.alsoIn), []);
  assert.deepEqual(first, beforeFirst);
  assert.equal(input.length, 3);
  assert.equal(input[0], first);
});
