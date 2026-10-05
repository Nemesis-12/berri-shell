// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/Times.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

test("pad", () => {
  assert.equal(lib.pad(5), "05");
  assert.equal(lib.pad(12), "12");
  assert.equal(lib.pad(7, 4), "0007");
});

test("day keys and day numbers round trip", () => {
  assert.equal(lib.dayKey(new Date(2026, 8, 3)), "2026-09-03");
  assert.equal(lib.dayNum("1970-01-02"), 1);
  assert.equal(lib.keyOfDayNum(lib.dayNum("2026-02-28") + 1), "2026-03-01");
  assert.equal(lib.keyOfDayNum(lib.dayNum("2024-02-28") + 1), "2024-02-29");
});

test("minutesSeconds", () => {
  assert.equal(lib.minutesSeconds(187), "3:07");
  assert.equal(lib.minutesSeconds(-4), "0:00");
  assert.equal(lib.minutesSeconds(undefined), "0:00");
  assert.equal(lib.minutesSeconds(59.9), "0:59");
});

test("clock text", () => {
  assert.equal(lib.clockText("15:05", false), "3:05 PM");
  assert.equal(lib.clockText("00:30", false), "12:30 AM");
  assert.equal(lib.clockText("12:00", false), "12:00 PM");
  assert.equal(lib.clockText("09:05", true), "09:05");
  assert.equal(lib.clockText("", false), "");
  assert.equal(lib.clockOfDate(new Date(2026, 8, 30, 7, 18), false), "7:18 AM");
});

const now = Date.UTC(2026, 8, 30, 12, 0, 0);
const ago = (min) => now - min * 60000;

test("age text, short styles", () => {
  assert.equal(lib.ageText(ago(0), now, "short"), "now");
  assert.equal(lib.ageText(ago(3), now, "short"), "3m");
  assert.equal(lib.ageText(ago(125), now, "short"), "2h");
  assert.equal(lib.ageText(ago(3000), now, "short"), "50h");
  assert.equal(lib.ageText(ago(0), now, "shortCaps"), "NOW");
  assert.equal(lib.ageText(ago(3), now, "shortCaps"), "3M");
  assert.equal(lib.ageText(ago(240), now, "shortCaps"), "4H");
  assert.equal(lib.ageText(ago(2 * 1440), now, "shortCaps"), "2D");
});

test("age text, ago style rounds and has a dash for no stamp", () => {
  assert.equal(lib.ageText(0, now, "ago"), "—");
  assert.equal(lib.ageText(ago(0.4), now, "ago"), "just now");
  assert.equal(lib.ageText(ago(12), now, "ago"), "12m ago");
  assert.equal(lib.ageText(ago(90), now, "ago"), "2h ago");
  assert.equal(lib.ageText(ago(2 * 1440), now, "ago"), "2d ago");
});

test("age text, agoOrDate style", () => {
  assert.equal(lib.ageText(new Date(ago(12)), now, "agoOrDate"), "12m ago");
  assert.equal(lib.ageText(new Date(ago(180)), now, "agoOrDate"), "3h ago");
  assert.equal(lib.ageText(new Date(ago(1600)), now, "agoOrDate"), "yesterday");
  assert.equal(lib.ageText(new Date(ago(5 * 1440)), now, "agoOrDate"), "5d ago");
  const old = new Date(2026, 7, 14, 12);
  assert.equal(lib.ageText(old, now, "agoOrDate"), "Aug 14");
});

test("names", () => {
  assert.equal(lib.monthsShort[8], "Sep");
  assert.equal(lib.weekdaysLong[0], "Sunday");
  assert.equal(lib.monthsLong.length, 12);
  assert.equal(lib.weekdaysShort.length, 7);
});

test("duration text has one format for every view", () => {
  assert.equal(lib.duration(7500), "2H 05M");
  assert.equal(lib.duration(0), "0H 00M");
  assert.equal(lib.duration(4 * 3600 + 12 * 60 + 59), "4H 12M");
  assert.equal(lib.duration(86400 + 3 * 3600 + 59), "1D 3H");
  assert.equal(lib.duration(2 * 86400 + 5 * 60), "2D 0H");
  assert.equal(lib.duration(-5), "0H 00M");
  assert.equal(lib.duration(undefined), "0H 00M");
});

test("duration options keep the battery and daylight wording", () => {
  assert.equal(lib.duration(37440, { round: true, pad: false, days: false }), "10H 24M");
  assert.equal(lib.duration(3570, { round: true, pad: false, days: false }), "1H 0M");
  assert.equal(lib.duration(43980, { round: true, pad: false, days: false, lower: true }), "12h 13m");
  assert.equal(lib.duration(100000, { days: false }), "27H 46M");
});

test("date shift", () => {
  assert.equal(lib.addDays("2026-02-28", 1), "2026-03-01");
  assert.equal(lib.addDays("2024-02-28", 1), "2024-02-29");
  assert.equal(lib.addDays("2026-01-01", -1), "2025-12-31");
  assert.equal(lib.addDays("2026-03-28", 2), "2026-03-30");
  assert.equal(lib.daysBetween("2026-03-28", "2026-04-02"), 5);
  assert.equal(lib.daysBetween("2026-04-02", "2026-03-28"), -5);
});
