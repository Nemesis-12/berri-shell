// Run: node --test berri-shell/tests/quick-add.test.mjs
// QuickAddParser.js is a QML library (".pragma library"), so it is evaluated in a vm context.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs
  .readFileSync(new URL("../logic/QuickAddParser.js", import.meta.url), "utf8")
  .replace(/^\.(pragma|import).*$/gm, "");
const times = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/Times.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), times);
const lib = vm.createContext({ Times: times });
vm.runInContext(source, lib);

const plain = (value) => JSON.parse(JSON.stringify(value));
// Tue 2026-09-29 is "today"; the selected day is Wed 2026-09-30 unless a test says otherwise.
const today = new Date(2026, 8, 29);
const selected = new Date(2026, 8, 30);
const parse = (text, sel = selected) => plain(lib.parse(text, today, sel, 1, false));
const labels = (p) => p.tokens.map((t) => t.text);

test("Dentist fri 3pm #e93", () => {
  const p = parse("Dentist fri 3pm #e93");
  assert.deepEqual(
    { kind: p.kind, title: p.title, date: p.date, time: p.time, end: p.end, color: p.color, repeat: p.repeat },
    { kind: "event", title: "Dentist", date: "2026-10-02", time: "15:00", end: "16:00", color: "#ee9933", repeat: "none" },
  );
  assert.deepEqual(labels(p), ["Event", "Fri Oct 2", "3:00 PM\u20134:00 PM", "#ee9933", "\u21B2"]);
});

test("task pay rent every month", () => {
  const p = parse("task pay rent every month");
  assert.equal(p.kind, "task");
  assert.equal(p.title, "pay rent");
  assert.equal(p.repeat, "monthly");
  assert.equal(p.date, "2026-09-30");
  assert.equal(p.time, null);
  assert.deepEqual(labels(p), ["Task", "Wed Sep 30", "Monthly", "\u21B2"]);
});

test("remind me to call Jo tomorrow 6pm", () => {
  const p = parse("remind me to call Jo tomorrow 6pm");
  assert.equal(p.kind, "reminder");
  assert.equal(p.title, "call Jo");
  assert.equal(p.date, "2026-09-30");
  assert.equal(p.time, "18:00");
  assert.equal(p.end, null);
});

test("weekday names count from today; the same weekday is today", () => {
  assert.equal(parse("lunch mon 12:30").date, "2026-10-05");
  assert.equal(parse("lunch tue 12:30").date, "2026-09-29");
  assert.equal(parse("lunch next fri").date, "2026-10-02");
});

test("12am is midnight and 12pm is noon", () => {
  assert.equal(parse("x 12am").time, "00:00");
  assert.equal(parse("x 12pm").time, "12:00");
  assert.equal(parse("x at noon").time, "12:00");
});

test("no date uses the selected day; no time makes an all-day event", () => {
  const p = parse("Water plants", new Date(2026, 9, 7));
  assert.equal(p.date, "2026-10-07");
  assert.equal(p.allDay, true);
  assert.equal(p.kind, "event");
  assert.equal(p.time, null);
  assert.equal(labels(p)[0], "All-day");
});

test("time range with one am/pm marker", () => {
  const p = parse("workshop 3-4pm");
  assert.equal(p.time, "15:00");
  assert.equal(p.end, "16:00");
  assert.equal(p.title, "workshop");
});

test("numbers that are not times stay in the title", () => {
  const p = parse("read chapter 3-4");
  assert.equal(p.title, "read chapter 3-4");
  assert.equal(p.time, null);
});

test("dates: month day, day month, d/m style, in N days", () => {
  assert.equal(parse("a sep 30").date, "2026-09-30");
  assert.equal(parse("a 3rd oct").date, "2026-10-03");
  assert.equal(parse("a 9/30").date, "2026-09-30");
  assert.equal(parse("a in 3 days").date, "2026-10-02");
  assert.equal(parse("a next week").date, "2026-10-06");
  // More than 60 days back: next year.
  assert.equal(parse("a jan 5").date, "2027-01-05");
  // Not a real date: stays in the title, day falls back to the selected one.
  assert.equal(parse("a feb 31").date, "2026-09-30");
});

test("every weekday repeats weekly from that weekday", () => {
  const p = parse("climbing every monday 7pm");
  assert.equal(p.repeat, "weekly");
  assert.equal(p.date, "2026-10-05");
  assert.deepEqual(p.byDay, [1]);
  assert.equal(p.title, "climbing");
});

test("repeat words", () => {
  assert.equal(parse("a every day").repeat, "daily");
  assert.equal(parse("a weekly").repeat, "weekly");
  assert.equal(parse("a every year").repeat, "yearly");
});

test("tonight sets 20:00; empty title asks for one", () => {
  const p = parse("tonight");
  assert.equal(p.time, "20:00");
  assert.equal(p.title, "");
  assert.deepEqual(labels(p).slice(-1), ["needs a title"]);
});

test("hint for an empty line names the selected day", () => {
  assert.equal(plain(lib.emptyHint(today))[0].text, "\u21B2 adds to Tue Sep 29 \u00B7 fri 3pm #e93");
});

test("24-hour hint", () => {
  const p = plain(lib.parse("x fri 3pm", today, selected, 1, true));
  assert.equal(p.tokens[2].text, "15:00\u201316:00");
});

test("tomorrow crosses year and leap-day boundaries with padded clock text", () => {
  for (const [reference, date, day] of [
    [new Date(2025, 11, 31), "2026-01-01", "Thu Jan 1"],
    [new Date(2024, 1, 28), "2024-02-29", "Thu Feb 29"],
  ]) {
    const visit = plain(lib.parse("Visit tomorrow 9:05am", reference, reference, 1, true));
    assert.deepEqual(
      { date: visit.date, time: visit.time, end: visit.end, tokens: labels(visit) },
      { date, time: "09:05", end: "10:05", tokens: ["Event", day, "09:05\u201310:05", "\u21B2"] },
    );
  }
});

test("hex colors: #rrggbb is read, invalid hex stays in the title, no color gives null", () => {
  const p = parse("Party #A1B2C3 fri");
  assert.equal(p.color, "#a1b2c3");
  assert.equal(p.title, "Party");
  assert.equal(parse("Buy milk").color, null);
  for (const text of ["Fix #12345", "Fix #ggg", "Fix #work"]) {
    const q = parse(text);
    assert.equal(q.color, null);
    assert.equal(q.title, text);
  }
});

// Match ranges use the original input, with an exclusive end.
const match = (text, word) => ({ text: word, start: text.indexOf(word), end: text.indexOf(word) + word.length });

test("matched fields keep original ranges after other parts are removed", () => {
  const text = "  task: Dentist #E93 on fri at 9am weekly  ";
  const p = parse(text);
  assert.deepEqual(p.matches, {
    kind: match(text, "task:"),
    date: match(text, "on fri"),
    time: match(text, "at 9am"),
    end: null,
    color: match(text, "#E93"),
    repeat: match(text, "weekly"),
  });
  assert.deepEqual(p.named, { kind: true, date: true, time: true, color: true, repeat: true });
  assert.equal(p.title, "Dentist");
});

test("explicit dates are named even when they equal the selected day", () => {
  for (const word of ["tomorrow", "sep 30", "30 sep", "9/30", "in 1 day", "every wednesday"]) {
    const text = "Visit " + word;
    const p = parse(text);
    assert.equal(p.date, "2026-09-30");
    assert.equal(p.named.date, true);
    assert.deepEqual(p.matches.date, match(text, word));
  }
  const invalid = parse("Visit feb 31");
  assert.equal(invalid.named.date, false);
  assert.equal(invalid.matches.date, null);
  assert.equal(invalid.title, "Visit feb 31");
});

test("default reminder time has no match but explicit 09:00 does", () => {
  const p = parse("remind me to call Jo");
  assert.equal(p.time, "09:00");
  assert.equal(p.named.time, false);
  assert.equal(p.matches.time, null);
  for (const word of ["9am", "09:00", "at 9:00", "noon"]) {
    const text = "remind me to call Jo " + word;
    const q = parse(text);
    assert.equal(q.named.time, true);
    assert.deepEqual(q.matches.time, match(text, word));
  }
  const tonight = parse("call Jo tonight");
  assert.equal(tonight.time, "20:00");
  assert.equal(tonight.named.time, true);
  assert.deepEqual(tonight.matches.time, match("call Jo tonight", "tonight"));
  const explicit = parse("call Jo tonight 9am");
  assert.equal(explicit.time, "09:00");
  assert.deepEqual(explicit.matches.time, match("call Jo tonight 9am", "9am"));
});

test("time ranges name the end, while a default end has no match", () => {
  const text = "Visit from 9-10am";
  const p = parse(text);
  assert.deepEqual(p.matches.time, match(text, "from 9-10am"));
  assert.deepEqual(p.matches.end, p.matches.time);
  assert.equal(p.end, "10:00");
  const single = parse("Visit 9am");
  assert.equal(single.end, "10:00");
  assert.equal(single.matches.end, null);
  const allDay = parse("Visit all-day 9am");
  assert.equal(allDay.named.kind, true);
  assert.equal(allDay.named.time, false);
  assert.equal(allDay.time, null);
  assert.deepEqual(allDay.matches.time, match("Visit all-day 9am", "9am"));
});

test("color matches keep the entered tag and reject invalid tags", () => {
  for (const word of ["#E93", "#A1B2C3"]) {
    const text = "Party " + word;
    const p = parse(text);
    assert.equal(p.named.color, true);
    assert.deepEqual(p.matches.color, match(text, word));
  }
  const p = parse("Party #work");
  assert.equal(p.named.color, false);
  assert.equal(p.matches.color, null);
});

test("deleting text clears matches and restores defaults on each parse", () => {
  const full = parse("remind me to Visit tomorrow 9am #E93 weekly");
  assert.deepEqual(full.named, { kind: true, date: true, time: true, color: true, repeat: true });
  const reminder = parse("remind me to Visit");
  assert.deepEqual(reminder.named, { kind: true, date: false, time: false, color: false, repeat: false });
  assert.equal(reminder.time, "09:00");
  const p = parse("Visit");
  assert.deepEqual(p.named, { kind: false, date: false, time: false, color: false, repeat: false });
  assert.deepEqual(p.matches, { kind: null, date: null, time: null, end: null, color: null, repeat: null });
  assert.equal(p.date, "2026-09-30");
  assert.equal(p.time, null);
  assert.equal(p.color, null);
  assert.equal(p.repeat, "none");
  assert.equal(p.allDay, true);
  const empty = parse("");
  assert.deepEqual(empty.named, p.named);
  assert.deepEqual(empty.matches, p.matches);
  assert.equal(empty.title, "");
});

// Pins the parse of about 90 phrases. The file was recorded from the parser before it was split into
// named steps. Only the numeric issue reference cases differ (see the next test).
test("recorded phrases parse to the same fields", () => {
  const recorded = JSON.parse(fs.readFileSync(new URL("./fixtures/quick-add-phrases.json", import.meta.url), "utf8"));
  assert.ok(recorded.length >= 50);
  for (const { text, result } of recorded) {
    assert.deepEqual(plain(lib.parse(text, today, selected, 1, false)), result, JSON.stringify(text));
  }
});

test("a number after # stays in the title; hex words with letters stay colors", () => {
  const issue = parse("Fix bug #123 tomorrow");
  assert.equal(issue.title, "Fix bug #123");
  assert.equal(issue.color, null);
  assert.equal(issue.named.color, false);
  assert.equal(issue.matches.color, null);
  assert.equal(issue.date, "2026-09-30");
  const hex = parse("x #12a");
  assert.equal(hex.color, "#1122aa");
  assert.equal(hex.title, "x");
  // Digits with a leading zero and six digits are still colors.
  assert.equal(parse("x #000").color, "#000000");
  assert.equal(parse("x #123456").color, "#123456");
  // Issue number followed by hex color: issue stays in title, color is read.
  const issueAndColor = parse("Fix bug #123 #f00 tomorrow");
  assert.equal(issueAndColor.title, "Fix bug #123");
  assert.equal(issueAndColor.color, "#ff0000");
  assert.equal(issueAndColor.named.color, true);
  assert.equal(issueAndColor.date, "2026-09-30");
});
