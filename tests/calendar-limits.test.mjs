// A hostile feed must not freeze a month query. Work is limited, and a feed over the limit is rejected.
import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./fixtures/calendar-code.mjs";

process.env.TZ = "UTC";
const Queries = calendarModule("CalendarQueries.js");
const Items = calendarModule("CalendarItems.js");

// A compact feed record. Every record needs only the fields that differ from this one.
function record(i, fields) {
  return { uid: "u" + i, kind: "event", title: "T" + i, date: "2026-10-01", time: "10:00", end: "11:00", endDate: null, repeat: "none", ...fields };
}

// One month query over feeds made of `records`. Returns the days, the time in ms, and the shown occurrence count.
function monthQuery(records, year = 2026, month = 10) {
  const projection = Queries.projectStoredCalendars([{ id: "f", name: "f", kind: "link", color: "blue", records, colorOverrides: {}, url: "https://feed.test/x" }]);
  const start = performance.now();
  const days = Queries.storedItemsInMonth(projection, year, month);
  const ms = performance.now() - start;
  const count = Object.values(days).reduce((sum, list) => sum + list.length, 0);
  return { days, ms, count, limited: days.limited === true };
}

// Generous bound for CI machines. The rule is "under 100 ms or rejected", and a rejection is the checked outcome.
const SLOW_CI_MS = 3000;

test("a daily event that spans the years 1000 to 9999 is rejected quickly", () => {
  const { ms, limited, count } = monthQuery([record(0, { date: "1000-01-01", time: null, end: null, endDate: "9999-12-31", repeat: "daily" })]);
  assert.equal(limited, true);
  assert.equal(count, 0);
  assert.ok(ms < SLOW_CI_MS, `took ${ms} ms`);
});

test("60,000 counted records in the month are rejected quickly", () => {
  const { ms, limited, count } = monthQuery(Array.from({ length: 60000 }, (_, i) => record(i, { repeat: "daily", count: 1000000 })));
  assert.equal(limited, true);
  assert.ok(count > 0 && count <= 20000, `shown: ${count}`);
  assert.ok(ms < SLOW_CI_MS, `took ${ms} ms`);
});

test("60,000 counted records that start years before the month are rejected quickly", () => {
  const { ms, limited } = monthQuery(Array.from({ length: 60000 }, (_, i) => record(i, { date: "1000-01-01", repeat: "weekly", count: 1000000 })));
  assert.equal(limited, true);
  assert.ok(ms < SLOW_CI_MS, `took ${ms} ms`);
});

test("a normal feed is not rejected", () => {
  const records = [
    record(0, { date: "2026-09-01", repeat: "daily", count: 100 }),
    record(1, { date: "2020-01-06", repeat: "weekly", byDay: [1] }),
    ...Array.from({ length: 300 }, (_, i) => record(10 + i, { date: "2026-10-" + String(1 + (i % 28)).padStart(2, "0") })),
  ];
  const { limited, count } = monthQuery(records);
  assert.equal(limited, false);
  assert.equal(count, 31 + 4 + 300);
});

test("a long multi-day event still shows on each day of the month it covers", () => {
  const { days, limited } = monthQuery([record(0, { date: "2020-01-01", time: null, end: null, endDate: "2030-01-01" })]);
  assert.equal(limited, false);
  assert.equal(Object.keys(days).length, 31);
  assert.equal(days["2026-10-17"].length, 1);
});

test("a counted daily series with an interval ends on its last counted day", () => {
  // 40 occurrences, every 2 days from 2026-09-01: the last one is on 2026-11-18. October holds the odd days 1 to 31.
  const { days } = monthQuery([record(0, { date: "2026-09-01", repeat: "daily", interval: 2, count: 40 })]);
  assert.deepEqual(Object.keys(days), Array.from({ length: 16 }, (_, i) => "2026-10-" + String(1 + 2 * i).padStart(2, "0")));
  const november = monthQuery([record(0, { date: "2026-09-01", repeat: "daily", interval: 2, count: 40 })], 2026, 11).days;
  assert.deepEqual(Object.keys(november), ["2026-11-02", "2026-11-04", "2026-11-06", "2026-11-08", "2026-11-10", "2026-11-12", "2026-11-14", "2026-11-16", "2026-11-18"]);
});

test("a counted weekly series ends after its count", () => {
  // Mondays from 2026-09-07, 5 occurrences: Sep 7, 14, 21, 28 and Oct 5.
  const { days } = monthQuery([record(0, { date: "2026-09-07", repeat: "weekly", count: 5 })]);
  assert.deepEqual(Object.keys(days), ["2026-10-05"]);
});

test("expand with no budget rejects one item that is too heavy and returns the others", () => {
  const heavy = Items.storedItem({ uid: "h", kind: "event", title: "H", date: "1000-01-01", endDate: "9999-12-31", repeat: "daily" });
  assert.deepEqual(Array.from(Items.expand(heavy, "2026-10-01", "2026-10-31")), []);
  const light = Items.storedItem({ uid: "l", kind: "event", title: "L", date: "2026-10-05" });
  assert.equal(Items.expand(light, "2026-10-01", "2026-10-31").length, 1);
});

test("a series with 50,000 changed occurrences is rejected quickly", () => {
  const changed = Array.from({ length: 50000 }, (_, i) => ({ from: "2026-10-01", cancelled: false, title: "C" + i, date: "2026-10-02", time: "09:00", end: null, endDate: null }));
  const { ms, limited, count } = monthQuery([record(0, { date: "2026-09-01", repeat: "daily", changedOccurrences: changed })]);
  assert.equal(limited, true);
  assert.equal(count, 0);
  assert.ok(ms < SLOW_CI_MS, `took ${ms} ms`);
});

test("a rejected item does not hide the other items of the month", () => {
  const records = [record(0, { date: "1000-01-01", time: null, end: null, endDate: "9999-12-31", repeat: "daily" }), record(1, { date: "2026-10-05" })];
  const { days, limited } = monthQuery(records);
  assert.equal(limited, true);
  assert.deepEqual(Object.keys(days), ["2026-10-05"]);
});
