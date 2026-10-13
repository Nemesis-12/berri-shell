// Run: node --test tests/quick-add-dates.test.mjs
// Date phrases of the quick-add parser, with a fixed "now". quick-add-time-zones.test.mjs runs this file in other time zones.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const times = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/Times.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), times);
const lib = vm.createContext({ Times: times });
vm.runInContext(fs.readFileSync(new URL("../logic/QuickAddParser.js", import.meta.url), "utf8")
  .replace(/^\.(pragma|import).*$/gm, ""), lib);

// Fri 2026-10-09 is "today" unless a test says otherwise. Other weekdays: Mon 2026-10-05 ... Thu 2026-10-08.
const friday = new Date(2026, 9, 9);
const parse = (text, now = friday) => JSON.parse(JSON.stringify(lib.parse(text, now, now, false)));

test("a bare weekday or 'this' weekday includes today", () => {
  for (const text of ["x friday", "x fri", "x this friday", "x on friday"]) {
    assert.equal(parse(text).date, "2026-10-09", text);
  }
  assert.equal(parse("x monday").date, "2026-10-12");
  assert.equal(parse("x this monday").date, "2026-10-12");
});

test("'next' weekday is the first such day after today, never today", () => {
  assert.equal(parse("x next friday").date, "2026-10-16");
  assert.equal(parse("x next fri").date, "2026-10-16");
  assert.equal(parse("x next friday").title, "x");
  assert.equal(parse("x next monday").date, "2026-10-12");
  assert.equal(parse("x next sunday").date, "2026-10-11");
  // From Monday: Tuesday is the day after, Monday is a week later.
  const monday = new Date(2026, 9, 5);
  assert.equal(parse("x next tuesday", monday).date, "2026-10-06");
  assert.equal(parse("x next monday", monday).date, "2026-10-12");
  assert.equal(parse("x monday", monday).date, "2026-10-05");
});

test("every weekday still starts on today when today has that weekday", () => {
  assert.equal(parse("x every friday").date, "2026-10-09");
});

test("tomorrow, today, in N days, next week", () => {
  assert.equal(parse("x tomorrow").date, "2026-10-10");
  assert.equal(parse("x today").date, "2026-10-09");
  assert.equal(parse("x in 3 days").date, "2026-10-12");
  assert.equal(parse("x next week").date, "2026-10-16");
});

test("month and day phrases", () => {
  assert.equal(parse("x oct 9").date, "2026-10-09");
  assert.equal(parse("x 9 oct").date, "2026-10-09");
  assert.equal(parse("x on October 12th").date, "2026-10-12");
  assert.equal(parse("x oct 12").title, "x");
  assert.equal(parse("x 10/12").date, "2026-10-12");
  // More than 60 days back: next year.
  assert.equal(parse("x jan 5").date, "2027-01-05");
  assert.equal(parse("x aug 20").date, "2026-08-20");
});

test("times next to dates", () => {
  const p = parse("x oct 9 3pm");
  assert.deepEqual([p.date, p.time, p.end, p.title], ["2026-10-09", "15:00", "16:00", "x"]);
  const q = parse("x tomorrow 9:30 to 11");
  assert.deepEqual([q.date, q.time, q.title], ["2026-10-10", "09:30", "x"]);
  assert.equal(parse("x friday at noon").time, "12:00");
});

test("Feb 29 is the next Feb 29 that exists, never March 1", () => {
  const dec2024 = new Date(2024, 11, 1);
  assert.equal(parse("Meeting Feb 29", dec2024).date, "2028-02-29");
  assert.equal(parse("Meeting 29 feb", dec2024).date, "2028-02-29");
  assert.equal(parse("Meeting 2/29", dec2024).date, "2028-02-29");
  assert.equal(parse("Meeting Feb 29", dec2024).title, "Meeting");
  // A leap year with the day still ahead, and the same year once it passed.
  assert.equal(parse("Meeting Feb 29", new Date(2028, 0, 10)).date, "2028-02-29");
  assert.equal(parse("Meeting Feb 29", new Date(2028, 5, 1)).date, "2032-02-29");
  // 2100 is not a leap year.
  assert.equal(parse("Meeting Feb 29", new Date(2096, 5, 1)).date, "2104-02-29");
  // Dates that never exist stay in the title.
  const never = parse("Meeting Feb 30", dec2024);
  assert.equal(never.title, "Meeting Feb 30");
  assert.equal(never.date, "2024-12-01");
});

test("ISO dates are read", () => {
  const p = parse("review on 2026-10-09 at 3pm");
  assert.deepEqual([p.title, p.date, p.time], ["review", "2026-10-09", "15:00"]);
  assert.equal(parse("x 2027-02-03").date, "2027-02-03");
  assert.equal(parse("x 2026-1-5").date, "2026-01-05");
  // A past date is kept as written.
  assert.equal(parse("x 2025-12-31").date, "2025-12-31");
  assert.equal(parse("x 2028-02-29").date, "2028-02-29");
  // Not real dates stay in the title.
  for (const text of ["x 2026-02-30", "x 2026-13-01", "x 2026-00-10"]) {
    assert.equal(parse(text).title, text, text);
  }
});
