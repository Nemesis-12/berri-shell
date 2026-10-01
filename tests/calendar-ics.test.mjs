// Run: node berri-shell/tests/calendar-ics.test.mjs
// The calendar code runs with its real QML imports in separate test contexts.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarCode } from "./fixtures/calendar-code.mjs";

process.env.TZ = "America/Chicago";

const ics = calendarCode();

// The vm context has its own Array/Object, so results are copied before deepEqual.
const plain = (value) => JSON.parse(JSON.stringify(value));
const days = (item, from, to) => plain(ics.expand(item, from, to).map((o) => o.date));
const item = (fields) => ics.makeItem({ title: "x", ...fields });

test("round trip keeps every field", () => {
  const cal = ics.emptyCalendar();
  cal.items.push(
    item({ uid: "a", kind: "event", title: "Dentist", date: "2026-10-02", time: "15:00", end: "16:00", color: "green" }),
    item({ uid: "b", kind: "event", title: "Flight", date: "2026-10-10", endDate: "2026-10-12" }),
    item({ uid: "c", kind: "task", title: "Pay rent", date: "2026-10-01", color: "#e93", repeat: "monthly", doneDates: ["2026-10-01"], exdates: ["2026-12-01"] }),
    item({ uid: "d", kind: "task", title: "Backup", date: "2026-10-03", doneDates: ["2026-10-03"] }),
    item({ uid: "e", kind: "reminder", title: "Water plants", date: "2026-10-04", time: "08:00", repeat: "weekly", interval: 2 }),
  );
  const text = ics.writeCalendar(cal);
  assert.match(text, /^BEGIN:VCALENDAR\r\n/);
  assert.match(text, /DTSTART;VALUE=DATE:20261010\r\nDTEND;VALUE=DATE:20261013\r\n/); // all-day, exclusive end
  assert.match(text, /DTSTART:20261002T150000\r\nDTEND:20261002T160000\r\n/); // timed, floating
  assert.match(text, /STATUS:COMPLETED/); // done task
  assert.match(text, /X-BERRI-KIND:reminder[\s\S]*BEGIN:VALARM[\s\S]*TRIGGER:PT0S/); // reminder with alarm
  assert.match(text, /RRULE:FREQ=WEEKLY;INTERVAL=2/);
  const again = ics.readCalendar(text);
  assert.deepEqual(plain(again.items.map(({ sourceDates, ...fields }) => fields)), plain(cal.items));
  assert.equal(ics.writeCalendar(again), text);
});

test("color is stored as X-BERRI-COLOR; accent is not written", () => {
  const cal = ics.emptyCalendar();
  cal.items.push(
    item({ uid: "a", date: "2026-10-01", color: "#ABC" }),
    item({ uid: "b", date: "2026-10-01", color: "nonsense" }),
    item({ uid: "c", date: "2026-10-01", color: "blue" }),
  );
  const text = ics.writeCalendar(cal);
  assert.match(text, /X-BERRI-COLOR:#aabbcc\r\n/);
  assert.match(text, /X-BERRI-COLOR:blue\r\n/);
  assert.equal(text.match(/X-BERRI-COLOR/g).length, 2);
  assert.deepEqual(plain(ics.readCalendar(text).items.map((i) => i.color)), ["#aabbcc", "accent", "blue"]);
  const occurrence = ics.itemsInMonth(ics.readCalendar(text).items, 2026, 10)["2026-10-01"][0];
  assert.equal(occurrence.color, "#aabbcc");
});

test("old tag in CATEGORIES becomes a color; other categories stay raw", () => {
  const event = (lines) => ics.readCalendar(["BEGIN:VCALENDAR", "BEGIN:VEVENT", "UID:x", "SUMMARY:s", "DTSTART;VALUE=DATE:20261001", ...lines, "END:VEVENT", "END:VCALENDAR", ""].join("\r\n")).items[0];
  assert.deepEqual(
    ["personal", "work", "health", "home", "Work", "other"].map((t) => event([`CATEGORIES:${t}`]).color),
    ["accent", "blue", "green", "yellow", "blue", "accent"],
  );
  assert.equal(event(["CATEGORIES:work", "X-BERRI-COLOR:red"]).color, "red");
  const foreign = event(["CATEGORIES:Family,Trip"]);
  assert.deepEqual(plain(foreign.raw), ["CATEGORIES:Family,Trip"]);
  const cal = ics.emptyCalendar();
  cal.items.push(event(["CATEGORIES:work"]), foreign);
  const text = ics.writeCalendar(cal);
  assert.match(text, /X-BERRI-COLOR:blue/);
  assert.doesNotMatch(text, /CATEGORIES:work/);
  assert.match(text, /CATEGORIES:Family,Trip/);
});

test("long lines fold at 75 octets and text escapes both ways", () => {
  const title = "Ünï, cödé; \\ path\nsecond line " + "é".repeat(80);
  const cal = ics.emptyCalendar();
  cal.items.push(item({ title, date: "2026-10-01" }));
  const text = ics.writeCalendar(cal);
  for (const line of text.split("\r\n")) assert.ok(Buffer.byteLength(line) <= 75, line);
  assert.match(text, /\\,/);
  assert.match(text, /\;/);
  assert.match(text, /\\n/);
  assert.equal(ics.readCalendar(text).items[0].title, title);
});

test("recurrence: daily, weekly, month-end, yearly, leap day", () => {
  assert.deepEqual(days(item({ date: "2026-10-01", repeat: "daily", interval: 2 }), "2026-10-01", "2026-10-07"),
    ["2026-10-01", "2026-10-03", "2026-10-05", "2026-10-07"]);
  assert.deepEqual(days(item({ date: "2026-10-01", repeat: "weekly" }), "2026-10-20", "2026-11-05"),
    ["2026-10-22", "2026-10-29", "2026-11-05"]);
  // Monthly on the 31st: months without a 31st are skipped.
  assert.deepEqual(days(item({ date: "2026-01-31", repeat: "monthly" }), "2026-01-01", "2026-06-30"),
    ["2026-01-31", "2026-03-31", "2026-05-31"]);
  assert.deepEqual(days(item({ date: "2024-02-29", repeat: "yearly" }), "2024-01-01", "2032-12-31"),
    ["2024-02-29", "2028-02-29", "2032-02-29"]);
  assert.deepEqual(days(item({ date: "2026-10-05", repeat: "weekly", byDay: [1, 3] }), "2026-10-05", "2026-10-14"),
    ["2026-10-05", "2026-10-07", "2026-10-12", "2026-10-14"]);
  assert.deepEqual(days(item({ date: "2026-10-01", repeat: "daily", count: 3 }), "2026-10-01", "2026-12-31"),
    ["2026-10-01", "2026-10-02", "2026-10-03"]);
  assert.deepEqual(days(item({ date: "2026-10-01", repeat: "daily", until: "2026-10-02" }), "2026-10-01", "2026-12-31"),
    ["2026-10-01", "2026-10-02"]);
  assert.deepEqual(days(item({ date: "2026-10-01", repeat: "daily" }), "2026-09-01", "2026-09-30"), []);
});

test("delete and move one occurrence with EXDATE", () => {
  const series = item({ uid: "s", title: "Climbing", date: "2026-10-01", time: "19:00", end: "21:00", repeat: "weekly", doneDates: ["2026-10-08"] });
  const { item: rest, created } = ics.moveOccurrence(series, "2026-10-08", "2026-10-09", { time: "18:00" });
  assert.deepEqual(plain(rest.exdates), ["2026-10-08"]);
  assert.equal(created.repeat, "none");
  assert.notEqual(created.uid, "s");
  assert.deepEqual(plain([created.date, created.time, created.doneDates]), ["2026-10-09", "18:00", ["2026-10-09"]]);
  const month = ics.itemsInMonth([rest, created], 2026, 10);
  assert.deepEqual(plain(Object.keys(month).sort()), ["2026-10-01", "2026-10-09", "2026-10-15", "2026-10-22", "2026-10-29"]);
  // The EXDATE survives a save and load.
  const cal = ics.emptyCalendar();
  cal.items.push(rest);
  assert.deepEqual(plain(ics.readCalendar(ics.writeCalendar(cal)).items[0].exdates), ["2026-10-08"]);
  assert.equal(ics.withoutOccurrence(item({ date: "2026-10-01" }), "2026-10-01"), null);
});

test("done state and day queries", () => {
  const task = item({ kind: "task", title: "Pay rent", date: "2026-10-01", repeat: "monthly" });
  const ticked = ics.withDone(task, "2026-11-01", true);
  assert.deepEqual(plain(ics.itemsOn([ticked], "2026-11-01").map((o) => o.done)), [true]);
  assert.deepEqual(plain(ics.itemsOn([ticked], "2026-10-01").map((o) => o.done)), [false]);
  const mixed = [item({ title: "b", date: "2026-10-01", time: "09:00" }), item({ title: "a", date: "2026-10-01" }), item({ title: "c", date: "2026-10-01", time: "08:00" })];
  assert.deepEqual(plain(ics.itemsOn(mixed, "2026-10-01").map((o) => o.title)), ["a", "c", "b"]);
  assert.deepEqual(plain(ics.snoozeTarget("23:50", "2026-10-01", 15, "2026-09-01", "10:00")), { date: "2026-10-02", time: "00:05" });
});

test("unknown properties and components from other apps survive", () => {
  const foreign = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Other App//EN", "X-WR-CALNAME:Work", "CALSCALE:GREGORIAN",
    "BEGIN:VTIMEZONE", "TZID:Europe/Berlin", "END:VTIMEZONE",
    "BEGIN:VEVENT", "UID:ext-1", "DTSTAMP:20260101T000000Z", "SUMMARY:Standup",
    "DTSTART;TZID=Europe/Berlin:20261005T093000", "DTEND;TZID=Europe/Berlin:20261005T094500",
    "LOCATION:Room 4", "DESCRIPTION:Line one\\nline two", "ATTENDEE;CN=Sam:mailto:sam@example.com",
    "BEGIN:VALARM", "ACTION:AUDIO", "TRIGGER:-PT5M", "END:VALARM", "END:VEVENT",
    "BEGIN:VEVENT", "UID:ext-2", "DTSTAMP:20260101T000000Z", "RECURRENCE-ID:20261012T093000", "SUMMARY:Override", "END:VEVENT",
    "BEGIN:VJOURNAL", "UID:j1", "SUMMARY:Diary", "END:VJOURNAL", "END:VCALENDAR", "",
  ].join("\r\n");
  const cal = ics.readCalendar(foreign);
  assert.equal(cal.items.length, 1);
  assert.deepEqual([cal.items[0].title, cal.items[0].time, cal.items[0].end], ["Standup", "02:30", "02:45"]);
  // Edit a known field, save, load: everything foreign is still there.
  cal.items[0] = ics.applyChanges(cal.items[0], { title: "Daily standup" });
  const out = ics.writeCalendar(cal);
  for (const line of ["PRODID:-//Other App//EN", "X-WR-CALNAME:Work", "CALSCALE:GREGORIAN", "BEGIN:VTIMEZONE", "TZID:Europe/Berlin",
    "LOCATION:Room 4", "DESCRIPTION:Line one\\nline two", "ATTENDEE;CN=Sam:mailto:sam@example.com", "ACTION:AUDIO", "RECURRENCE-ID:20261012T093000", "BEGIN:VJOURNAL", "SUMMARY:Diary"]) {
    assert.ok(out.includes(line), "lost: " + line);
  }
  assert.match(out, /SUMMARY:Daily standup/);
  assert.equal(ics.writeCalendar(ics.readCalendar(out)), out);
});

test("due reminders use the alarm offset, skip done ones and find the next one", () => {
  const at = (d, h, m) => new Date(2026, 9, d, h, m).getTime();
  const items = [
    item({ uid: "r1", kind: "reminder", title: "Call", date: "2026-10-05", time: "10:00", alarmMinutes: 10 }),
    item({ uid: "r2", kind: "reminder", title: "Water", date: "2026-10-01", time: "08:00", repeat: "daily", doneDates: ["2026-10-06"] }),
    item({ uid: "t1", kind: "task", title: "Task", date: "2026-10-05", time: "09:00" }),
  ];
  const due = plain(ics.dueBetween(items, at(5, 7, 0), at(6, 9, 0)).map((d) => [d.uid, d.occurrenceDate, d.dueMs]));
  assert.deepEqual(due, [["r2", "2026-10-05", at(5, 8, 0)], ["r1", "2026-10-05", at(5, 9, 50)]]);
  // Exact ends: from is open, to is closed. The done day 2026-10-06 is skipped.
  assert.equal(ics.dueBetween(items, at(5, 9, 50), at(6, 9, 0)).length, 0);
  assert.equal(ics.nextDueMs(items, at(5, 9, 50), 30), at(7, 8, 0));
});

// ---- several calendars

const parsed = (name, body) =>
  ics.readCalendar(`BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${name ? `X-WR-CALNAME:${name}\r\n` : ""}${body}END:VCALENDAR\r\n`);
const event = (uid, date, extra = "") =>
  `BEGIN:VEVENT\r\nUID:${uid}\r\nSUMMARY:${uid}\r\nDTSTART;VALUE=DATE:${date}\r\n${extra}END:VEVENT\r\n`;

test("calendar name comes from X-WR-CALNAME and survives a round trip", () => {
  const cal = parsed("Public holidays", event("h1", "20261225"));
  assert.equal(ics.calendarName(cal), "Public holidays");
  assert.equal(ics.calendarName(ics.readCalendar(ics.writeCalendar(cal))), "Public holidays");
  assert.equal(ics.calendarName(parsed("", "")), "");
});

test("merge stamps calendar id and read-only flag, and hides hidden calendars", () => {
  const mine = parsed("", event("a", "20261201"));
  const feed = parsed("Feed", event("b", "20261201"));
  const off = parsed("Off", event("c", "20261201"));
  const merged = ics.mergeCalendars([
    { id: "berri", color: "accent", hidden: false, readOnly: false, items: mine.items },
    { id: "l-feed", color: "green", hidden: false, readOnly: true, items: feed.items },
    { id: "f-off", color: "red", hidden: true, readOnly: false, items: off.items },
  ]);
  const day = plain(ics.itemsOn(merged, "2026-12-01").map((o) => [o.uid, o.calendarId, o.readOnly, o.color]));
  assert.deepEqual(day, [["a", "berri", false, "accent"], ["b", "l-feed", true, "green"]]);
  assert.equal(off.items[0].calendarId, "f-off"); // hidden items are still stamped
});

test("an item keeps its own color, the default color follows the calendar", () => {
  const cal = parsed("", event("own", "20261201", "X-BERRI-COLOR:#e93\r\n") + event("plain", "20261202"));
  const merged = ics.mergeCalendars([{ id: "f-x", color: "blue", hidden: false, readOnly: false, items: cal.items }]);
  assert.deepEqual(plain(merged.map((i) => i.color)), ["#ee9933", "blue"]);
});

test("feedUrl accepts https and webcal only", () => {
  assert.equal(ics.feedUrl("webcal://x.org/a.ics"), "https://x.org/a.ics");
  assert.equal(ics.feedUrl("  HTTPS://x.org/a.ics "), "https://x.org/a.ics");
  assert.equal(ics.feedUrl("http://x.org/a.ics"), null);
  assert.equal(ics.feedUrl("https://"), null);
  assert.equal(ics.feedUrl("file:///etc/passwd"), null);
  assert.equal(ics.feedUrl("https://x.org/a b"), null);
  assert.equal(ics.linkHost("https://user@holidays.example.org/a/b.ics?x=1"), "holidays.example.org");
});

test("looksLikeCalendar, unusedColor and shortHash", () => {
  assert.equal(ics.looksLikeCalendar("BEGIN:VCALENDAR\r\nEND:VCALENDAR"), true);
  assert.equal(ics.looksLikeCalendar("<html>nope</html>"), false);
  assert.equal(ics.unusedColor(["accent", "blue"]), "green");
  assert.equal(ics.unusedColor(plain(ics.COLOR_PRESETS)), "accent");
  assert.equal(ics.shortHash("a"), ics.shortHash("a"));
  assert.notEqual(ics.shortHash("a"), ics.shortHash("b"));
});

test("curlError gives a short message", () => {
  assert.equal(ics.curlError(6), "Cannot reach the host");
  assert.equal(ics.curlError(28), "Timed out");
  assert.equal(ics.curlError(999), "Download failed");
});

test("link item color override shows on occurrences; other items keep the calendar color", () => {
  const feed = [item({ uid: "m1", date: "2026-10-03" }), item({ uid: "m2", date: "2026-10-04" })];
  const merged = ics.mergeCalendars([
    { id: "l-x", color: "blue", hidden: false, readOnly: true, colorOverrides: { m1: "#ee9933" }, items: feed },
  ]);
  const [a, b] = ics.itemsInMonth(merged, 2026, 10)["2026-10-03"].concat(ics.itemsInMonth(merged, 2026, 10)["2026-10-04"]);
  assert.equal(a.color, "#ee9933");
  assert.equal(a.hasOwnColor, true);
  assert.equal(a.readOnly, true);
  assert.equal(b.color, "blue");
  assert.equal(b.hasOwnColor, false);
  // the edit form reads the same color
  assert.equal(ics.withColorOverride(feed[0], { m1: "#ee9933" }).color, "#ee9933");
  assert.equal(ics.withColorOverride(feed[1], { m1: "#ee9933" }).color, feed[1].color);
});

test("cleared override falls back to the calendar color", () => {
  const feed = [item({ uid: "m1", date: "2026-10-03" })];
  const merged = ics.mergeCalendars([{ id: "l-x", color: "green", hidden: false, readOnly: true, colorOverrides: {}, items: feed }]);
  const occ = ics.itemsInMonth(merged, 2026, 10)["2026-10-03"][0];
  assert.equal(occ.color, "green");
  assert.equal(occ.hasOwnColor, false);
});

test("own color of a local item counts as hasOwnColor", () => {
  const items = [item({ uid: "a", date: "2026-10-03", color: "red" }), item({ uid: "b", date: "2026-10-03" })];
  const merged = ics.mergeCalendars([{ id: "berri", color: "accent", hidden: false, readOnly: false, items }]);
  const day = ics.itemsInMonth(merged, 2026, 10)["2026-10-03"];
  assert.deepEqual(plain(day.map((o) => [o.uid, o.hasOwnColor])).sort(), [["a", true], ["b", false]]);
});

test("stale overrides are pruned after a feed change", () => {
  const feed = [item({ uid: "m1", date: "2026-10-03" })];
  const kept = ics.pruneColorOverrides({ m1: "red", gone: "blue", bad: "nope" }, feed);
  assert.deepEqual(plain(kept), { m1: "red" });
  assert.deepEqual(plain(ics.pruneColorOverrides({ x: "blue", y: "zzz" }, null)), { x: "blue" });
});

test("newCalendarColor uses a valid wanted color, else the first unused preset", () => {
  assert.equal(ics.newCalendarColor("#E93", ["accent"]), "#ee9933");
  assert.equal(ics.newCalendarColor("red", ["accent"]), "red");
  assert.equal(ics.newCalendarColor("nope", ["accent", "blue"]), "green");
  assert.equal(ics.newCalendarColor(undefined, ["accent"]), "blue");
  assert.equal(ics.newCalendarColor("", []), "accent");
});

test("clearItemColors resets own colors so items show the calendar color", () => {
  const items = [item({ uid: "a", color: "red" }), item({ uid: "b" }), item({ uid: "c", color: "#e93" })];
  assert.equal(ics.clearItemColors(items), 2);
  assert.equal(ics.clearItemColors(items), 0);
  const [occ] = ics.mergeCalendars([{ id: "f-x", color: "blue", hidden: false, readOnly: false, items }]);
  assert.equal(occ.color, "blue");
  assert.equal(occ.hasOwnColor, false);
  assert.doesNotMatch(ics.writeCalendar({ ...ics.emptyCalendar(), items }), /X-BERRI-COLOR/);
});

test("clearing overrides makes link items use the calendar color", () => {
  const feed = [item({ uid: "a", date: "2026-10-05" })];
  const args = (overrides) => [{ id: "l-x", color: "green", hidden: false, readOnly: true, colorOverrides: overrides, items: feed }];
  assert.equal(ics.mergeCalendars(args({ a: "red" }))[0].color, "red");
  const after = ics.mergeCalendars(args(ics.pruneColorOverrides({}, null)))[0];
  assert.equal(after.color, "green");
  assert.equal(after.hasOwnColor, false);
});

// ---- the same event in several calendars shows once

const fixture = (name) => ics.readCalendar(fs.readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"));
const bayern = fixture("bayern.ics");
const dortmund = fixture("dortmund.ics");
const listOf = (id, cal, extra = {}) => ({ id, color: "blue", hidden: false, readOnly: true, colorOverrides: {}, items: cal.items, ...extra });
const matchDay = bayern.items.find((i) => i.title.includes("Dortmund")).date; // 31 Oct, or 1 Nov in far east time zones
const names = { "l-fcb": "Bayern München", "l-bvb": "Borussia Dortmund" };
const timed = (uid, title, start) =>
  `BEGIN:VEVENT\r\nUID:${uid}\r\nSUMMARY:${title}\r\nDTSTART:${start}\r\nEND:VEVENT\r\n`;

test("same uid in two feeds: shown once, first calendar kept", () => {
  const merged = ics.mergeCalendars([listOf("l-fcb", bayern), listOf("l-bvb", dortmund)]);
  const day = plain(ics.itemsOn(merged, matchDay));
  assert.equal(day.length, 1);
  assert.equal(day[0].calendarId, "l-fcb");
  assert.deepEqual(day[0].alsoIn, ["l-bvb"]); // without a names map the id is used
});

test("alsoIn uses calendar names, alsoInIds the ids", () => {
  const merged = ics.mergeCalendars([listOf("l-fcb", bayern), listOf("l-bvb", dortmund)]);
  const month = plain(ics.itemsInMonth(merged, +matchDay.slice(0, 4), +matchDay.slice(5, 7), names));
  const shown = month[matchDay];
  assert.equal(shown.length, 1);
  assert.deepEqual(shown[0].alsoIn, ["Borussia Dortmund"]);
  assert.deepEqual(shown[0].alsoInIds, ["l-bvb"]);
  assert.equal(shown[0].readOnly, true);
});

test("no uid match: same start and title match, a trailing score is ignored", () => {
  const a = parsed("A", timed("x1", "Team A - Team B", "20261101T120000Z"));
  const b = parsed("B", timed("y1", "  team a -  TEAM B (2-1)", "20261101T120000Z"));
  const other = parsed("C", timed("z1", "Team A - Team B", "20261101T130000Z")); // other time: not a duplicate
  const merged = ics.mergeCalendars([listOf("a", a), listOf("b", b), listOf("c", other)]);
  const day = plain(ics.itemsOn(merged, "2026-11-01"));
  assert.equal(day.length, 2);
  const kept = day.find((o) => o.calendarId === "a"); // the other-time copy is not a duplicate, whatever the time zone
  assert.equal(kept.calendarId, "a");
  assert.deepEqual(kept.alsoInIds, ["b"]);
});

test("entries of one calendar are never merged", () => {
  const twin = parsed("A", timed("x1", "Same", "20261101T120000Z") + timed("x2", "Same", "20261101T120000Z"));
  const merged = ics.mergeCalendars([listOf("a", twin)]);
  assert.equal(ics.itemsOn(merged, "2026-11-01").length, 2);
});

test("a copy with its own color is kept, an all-day copy needs the same date", () => {
  const a = parsed("A", event("u", "20261105"));
  const b = parsed("B", event("u", "20261105", "X-BERRI-COLOR:red\r\n"));
  const merged = ics.mergeCalendars([listOf("a", a, { readOnly: false }), listOf("b", b, { readOnly: false })]);
  const day = plain(ics.itemsOn(merged, "2026-11-05"));
  assert.equal(day.length, 1);
  assert.equal(day[0].calendarId, "b");
  assert.deepEqual(day[0].alsoInIds, ["a"]);
  assert.equal(day[0].readOnly, false);
});

test("a hidden first calendar does not count: the next copy is shown, without alsoIn", () => {
  const merged = ics.mergeCalendars([listOf("l-fcb", bayern, { hidden: true }), listOf("l-bvb", dortmund)]);
  const day = plain(ics.itemsOn(merged, matchDay));
  assert.equal(day.length, 1);
  assert.equal(day[0].calendarId, "l-bvb");
  assert.deepEqual(day[0].alsoIn, []);
});

test("countDuplicates counts feed items that already exist, by uid or by start and title", () => {
  const existing = ics.mergeCalendars([listOf("l-fcb", bayern)]);
  assert.equal(ics.countDuplicates(dortmund.items, existing), 1); // the shared match only
  const renamed = parsed("C", timed("new-uid", "Bayern München - Borussia Dortmund (3-1)", "20261031T173000Z"));
  assert.equal(ics.countDuplicates(renamed.items, existing), 1); // same start and title
  assert.equal(ics.countDuplicates(dortmund.items, []), 0);
});

test("dropDuplicateItems (reminders) keeps one copy of a shared item", () => {
  const a = parsed("A", timed("u", "Call", "20261101T120000Z"));
  const b = parsed("B", timed("u", "Call", "20261101T120000Z"));
  const merged = ics.mergeCalendars([listOf("a", a, { readOnly: false }), listOf("b", b, { readOnly: false })]);
  assert.equal(ics.dropDuplicateItems(merged).length, 1);
});

// Imported dates keep their source form when another field changes.
const importedCalendar = (lines, kind = "VEVENT") => ics.readCalendar([
  "BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:" + kind, "UID:imported",
  "SUMMARY:Imported", ...lines, "END:" + kind, "END:VCALENDAR", "",
].join("\r\n"));

for (const example of [
  { form: "date", start: "DTSTART;VALUE=DATE:20261005", end: "DTEND;VALUE=DATE:20261007",
    date: "2026-10-05", time: null, instant: null, zone: null },
  { form: "floating", start: "DTSTART:20261005T093027", end: "DTEND:20261005T103047",
    date: "2026-10-05", time: "09:30", instant: new Date(2026, 9, 5, 9, 30, 27).getTime(), zone: null },
  { form: "utc", start: "DTSTART:20261005T003027Z", end: "DTEND:20261005T013047Z",
    date: "2026-10-04", time: "19:30", instant: Date.UTC(2026, 9, 5, 0, 30, 27), zone: null },
  { form: "zone", start: "DTSTART;TZID=Europe/Berlin:20261005T093027", end: "DTEND;TZID=Europe/Berlin:20261005T103047",
    date: "2026-10-05", time: "02:30", instant: Date.UTC(2026, 9, 5, 7, 30, 27), zone: "Europe/Berlin" },
]) {
  test("round trip preserves " + example.form + " dates, instants and zone references", () => {
    const cal = importedCalendar([example.start, example.end]);
    const first = cal.items[0];
    assert.equal(first.date, example.date);
    assert.equal(first.time, example.time);
    assert.equal(first.sourceDates.start.form, example.form);
    assert.equal(first.sourceDates.start.tzid, example.zone);
    assert.equal(first.sourceDates.start.instantMs, example.instant);
    cal.items[0] = ics.applyChanges(first, { title: "Changed", date: first.date, time: first.time, end: first.end, endDate: first.endDate });
    const out = ics.writeCalendar(cal);
    assert.ok(out.includes(example.start + "\r\n"));
    assert.ok(out.includes(example.end + "\r\n"));
    const again = ics.readCalendar(out).items[0];
    assert.equal(again.sourceDates.start.instantMs, example.instant);
    assert.equal(again.sourceDates.start.tzid, example.zone);
    assert.deepEqual(plain(again.sourceDates.end), plain(first.sourceDates.end));
  });
}

test("edited dates keep the source zone and use its offset on the new date", () => {
  const cal = importedCalendar(["DTSTART;TZID=Europe/Berlin:20261005T093000", "DTEND;TZID=Europe/Berlin:20261005T103000"]);
  cal.items[0] = ics.applyChanges(cal.items[0], { date: "2026-11-05", time: "02:30", end: "03:30" });
  const out = ics.writeCalendar(cal);
  assert.match(out, /DTSTART;TZID=Europe\/Berlin:20261105T093000/);
  assert.match(out, /DTEND;TZID=Europe\/Berlin:20261105T103000/);
  const again = ics.readCalendar(out).items[0];
  assert.equal(again.sourceDates.start.instantMs, new Date(2026, 10, 5, 2, 30).getTime());
  assert.equal(again.sourceDates.start.tzid, "Europe/Berlin");
});

test("edited UTC, floating and date-only dates keep their forms", () => {
  for (const [start, expected] of [
    ["DTSTART:20261005T003000Z", "DTSTART:20261007T083000Z"],
    ["DTSTART:20261005T093000", "DTSTART:20261007T033000"],
    ["DTSTART;VALUE=DATE:20261005", "DTSTART;VALUE=DATE:20261007"],
  ]) {
    const cal = importedCalendar([start]);
    cal.items[0] = ics.applyChanges(cal.items[0], { date: "2026-10-07", time: cal.items[0].time === null ? null : "03:30" });
    assert.ok(ics.writeCalendar(cal).includes(expected + "\r\n"));
  }
});

test("an unknown zone stays intact until an edit, then uses UTC", () => {
  const cal = importedCalendar(["DTSTART;TZID=Unknown/Zone:20261005T093027"]);
  assert.match(ics.writeCalendar(cal), /DTSTART;TZID=Unknown\/Zone:20261005T093027/);
  cal.items[0] = ics.applyChanges(cal.items[0], { time: "10:30" });
  assert.match(ics.writeCalendar(cal), /DTSTART:20261005T153000Z/);
});

test("UNTIL, EXDATE and task DUE keep their source date forms", () => {
  const cal = importedCalendar([
    "DTSTART;TZID=Europe/Berlin:20261005T093000",
    "RRULE:FREQ=DAILY;UNTIL=20261105T083059Z",
    "EXDATE;TZID=Europe/Berlin:20261006T093000,20261007T093000",
  ]);
  cal.items[0] = ics.withoutOccurrence(cal.items[0], "2026-10-08");
  const out = ics.writeCalendar(cal);
  assert.match(out, /UNTIL=20261105T083059Z/);
  assert.match(out, /EXDATE;TZID=Europe\/Berlin:20261006T093000,20261007T093000/);
  assert.match(out, /EXDATE;TZID=Europe\/Berlin:20261008T093000/);
  const task = importedCalendar(["DUE:20261005T003027Z"], "VTODO");
  assert.match(ics.writeCalendar(task), /DUE:20261005T003027Z/);
});

test("calendar item keys select each copy and reject edits to read-only copies", () => {
  const copies = ics.mergeCalendars([
    { id: "a", items: [item({ uid: "same", title: "A", date: "2026-10-05" })] },
    { id: "b", items: [item({ uid: "same", title: "B", date: "2026-10-05" })] },
    { id: "link", readOnly: true, items: [item({ uid: "same", title: "Link", date: "2026-10-05" })] },
  ]);
  for (const [index, calendarId] of ["a", "b", "link"].entries()) {
    const key = ics.itemKey(calendarId, "same");
    assert.deepEqual(plain(ics.itemIdentity(key)), { calendarId, uid: "same" });
    assert.equal(ics.itemIndex(copies, key, false), index);
    assert.equal(ics.itemIndex(copies, key, true), calendarId === "link" ? -1 : index);
    const shown = ics.withItemIdentity(ics.expand(copies[index], "2026-10-05", "2026-10-05")[0]);
    assert.equal(shown.uid, key);
    assert.equal(shown.sourceUid, "same");
    assert.equal(shown.calendarId, calendarId);
  }
  assert.equal(ics.itemIndex(copies, "same", false), -1);
  assert.notEqual(ics.itemKey("a|b", "c"), ics.itemKey("a", "b|c"));
});

test("reminder actions keep the calendar of the selected copy", () => {
  const from = new Date(2026, 9, 5, 9).getTime();
  const reminders = ics.mergeCalendars(["a", "b"].map((id) => ({ id, items: [item({
    uid: "same", kind: "reminder", title: id, date: "2026-10-05", time: "10:00",
  })] })));
  const due = ics.dueBetween(reminders, from, from + 2 * 3600000);
  assert.deepEqual(plain(due.map((entry) => entry.calendarId)), ["a", "b"]);
  assert.notEqual(ics.itemKey(due[0].calendarId, due[0].uid), ics.itemKey(due[1].calendarId, due[1].uid));
});


test("a zero-duration imported event keeps its unchanged DTEND", () => {
  const cal = importedCalendar(["DTSTART:20261005T093027Z", "DTEND:20261005T093027Z"]);
  cal.items[0] = ics.applyChanges(cal.items[0], { title: "Changed" });
  assert.match(ics.writeCalendar(cal), /DTEND:20261005T093027Z/);
});

test("item field edits cannot change UID, calendar ownership or read-only state", () => {
  const original = ics.mergeCalendars([{ id: "a", items: [item({ uid: "same", date: "2026-10-05" })] }])[0];
  const changed = ics.applyChanges(original, { uid: "other", calendarId: "b", readOnly: true, title: "Changed" });
  assert.equal(changed.uid, "same");
  assert.equal(changed.calendarId, "a");
  assert.equal(changed.readOnly, false);
  assert.equal(changed.title, "Changed");
});

test("new floating recurrence limits keep their floating date-time form", () => {
  const cal = ics.emptyCalendar();
  cal.items.push(item({ date: "2026-10-05", time: "09:30", repeat: "daily", until: "2026-10-08" }));
  assert.match(ics.writeCalendar(cal), /UNTIL=20261008T235959\r\n/);
});

test("one calendar change updates rows, month items and reminders together", () => {
  const local = {
    id: "berri", name: "berri", kind: "local", color: "accent", hidden: false,
    file: "berri.ics", path: "/cal/berri.ics", updatedAt: 0, error: "",
    document: ics.emptyCalendar(),
  };
  const feed = {
    id: "feed", name: "Feed", kind: "link", color: "blue", hidden: false,
    file: "subscriptions/feed.ics", path: "/cal/subscriptions/feed.ics",
    url: "https://calendar.example.test/feed", updatedAt: 10, error: "",
    document: ics.emptyCalendar(),
  };
  local.document.items.push(item({ uid: "local", kind: "reminder", date: "2026-10-01", time: "09:00" }));
  feed.document.items.push(item({ uid: "remote", title: "Feed event", date: "2026-10-02" }));
  const check = (calendars, counts, shownDays, reminderUids) => {
    const result = ics.projectCalendars(calendars);
    assert.deepEqual(plain(result.calendars.map((calendar) => calendar.itemCount)), counts);
    assert.deepEqual(Object.keys(ics.itemsInMonth(result.items, 2026, 10, result.names)), shownDays);
    assert.deepEqual(plain(result.reminders.map((reminder) => reminder.uid)), reminderUids);
    return result;
  };
  const first = check([local, feed], [1, 1], ["2026-10-01", "2026-10-02"], ["local"]);
  assert.equal(first.itemPaths[ics.itemKey("feed", "remote")], feed.path);
  feed.document = ics.readCalendar("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:new\nDTSTART;VALUE=DATE:20261003\nSUMMARY:Refreshed\nEND:VEVENT\nEND:VCALENDAR\n");
  const refreshed = check([local, feed], [1, 1], ["2026-10-01", "2026-10-03"], ["local"]);
  assert.equal(refreshed.itemPaths[ics.itemKey("feed", "remote")], undefined);
  local.hidden = true;
  check([local, feed], [1, 1], ["2026-10-03"], []);
  local.hidden = false;
  local.document.items = [];
  check([local, feed], [0, 1], ["2026-10-03"], []);
  check([local], [0], [], []);
});

test("calendar date helpers keep day keys at month and year changes", () => {
  assert.equal(ics.keyOfDayNum(ics.dayNum("2024-02-29") + 1), "2024-03-01");
  assert.equal(ics.keyOfDayNum(ics.dayNum("2026-12-31") + 1), "2027-01-01");
  assert.equal(ics.toKey("2026-12-31T23:59:00"), "2026-12-31");
  assert.equal(ics.toKey(new Date(2026, 11, 31, 23, 59)), "2026-12-31");
});
