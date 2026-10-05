// Both calendar readers get the same feeds: readCalendar (editable calendars)
// and feed-to-records + expandCompactItem (subscribed calendars).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const zone = "America/Chicago";
process.env.TZ = zone;

const Format = calendarModule("CalendarFormat.js");
const Queries = calendarModule("CalendarQueries.js");
const manifest = new URL("../tools/feed-to-records/Cargo.toml", import.meta.url).pathname;
const feedsDir = new URL("./fixtures/feeds/", import.meta.url).pathname;

// Intended differences, by name:
// - order: the converter sorts records by local start; the editable reader keeps file order.
//   Items are compared by uid, so one uid per feed item is required.
// - location: the editable reader keeps LOCATION as a raw line; only subscriptions read it.
// - stamp (DTSTAMP), rawChildren, sourceDates and raw: editable items keep source text so a save writes it back unchanged.
//   Subscriptions are read-only and keep none of it.
const editableSourceText = ["raw", "rawChildren", "sourceDates", "stamp", "location"];

const build = spawnSync("cargo", ["build", "--offline", "--quiet", "--manifest-path", manifest], { encoding: "utf8" });
assert.equal(build.status, 0, build.stderr);
const converter = path.join(path.dirname(manifest), "target", "debug", "feed-to-records");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "berri-readers-"));

function withoutSourceText(item) {
  const shared = { ...item };
  for (const name of editableSourceText) delete shared[name];
  return JSON.parse(JSON.stringify(shared));
}

// Both readers' shared fields for one feed file, keyed by uid.
function readBoth(file) {
  const { editable, subscribed } = readLists(file, zone);
  const byUid = (items) => Object.fromEntries(items.map((item) => [item.uid, withoutSourceText(item)]));
  return { editable: byUid(editable), subscribed: byUid(subscribed) };
}

// Both readers' item lists for one feed file, read with `displayZone` as the display time zone.
function readLists(file, displayZone) {
  process.env.TZ = displayZone;
  const out = path.join(scratch, `${path.basename(file)}.json`);
  const run = spawnSync(converter, [file, out], { env: { ...process.env, TZ: displayZone }, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const subscribed = JSON.parse(fs.readFileSync(out, "utf8")).records.map(Format.expandCompactItem);
  const editable = Format.readCalendar(fs.readFileSync(file, "utf8")).items;
  process.env.TZ = zone;
  return { editable, subscribed };
}

// "HH:MM Title" lines per day of a month query, for each reader. Empty days are left out.
function monthBoth(name, year, month, displayZone) {
  const { editable, subscribed } = readLists(path.join(feedsDir, name), displayZone);
  const query = (calendar) => {
    process.env.TZ = displayZone;
    const days = Queries.storedItemsInMonth(Queries.projectStoredCalendars([calendar]), year, month);
    process.env.TZ = zone;
    return Object.fromEntries(Object.entries(days).map(([day, list]) => [day, Array.from(list, (o) => `${o.time} ${o.title}`)]));
  };
  const base = { id: "feed", name: "Feed", color: "accent", hidden: false, updatedAt: 0 };
  return {
    editable: query({ ...base, kind: "file", file: "feed.ics", document: { items: editable } }),
    subscribed: query({ ...base, kind: "link", url: "https://example.org/feed.ics", records: subscribed }),
  };
}

// The two real feeds one level up are part of the set.
const feedFiles = [
  ...fs.readdirSync(feedsDir).filter((file) => file.endsWith(".ics")).sort().map((file) => path.join(feedsDir, file)),
  ...["bayern.ics", "dortmund.ics"].map((file) => path.join(feedsDir, "..", file)),
];

for (const file of feedFiles) {
  test(`both readers give equal shared fields for ${path.basename(file)}`, () => {
    const { editable, subscribed } = readBoth(file);
    assert.ok(Object.keys(editable).length > 0);
    assert.deepEqual(subscribed, editable);
  });
}

test("a start time on 2026-10-05 at 09:00 without seconds gives that date and time in both readers", () => {
  const { editable, subscribed } = readBoth(path.join(feedsDir, "timed-no-seconds.ics"));
  for (const reader of [editable, subscribed]) {
    assert.equal(reader.t1.date, "2026-10-05");
    assert.equal(reader.t1.time, "09:00");
  }
});

function everyReader(name, year, month, displayZone, check) {
  const days = monthBoth(name, year, month, displayZone);
  for (const reader of ["editable", "subscribed"]) check(days[reader], reader);
}

test("a month query leaves out the cancelled event and keeps the normal one", () => {
  everyReader("cancelled.ics", 2026, 10, zone, (days) => {
    assert.deepEqual(days, { "2026-10-06": ["09:00 Normal"] });
  });
});

test("a monthly rule on the second Tuesday shows on 2026-11-10, and one on the last Friday on 2026-11-27", () => {
  everyReader("monthly-weekday.ics", 2026, 11, zone, (days) => {
    assert.deepEqual(days, { "2026-11-10": ["10:00 Second Tuesday"], "2026-11-27": ["10:00 Last Friday"] });
  });
});

test("a moved occurrence shows at its new time, and its old time and a cancelled occurrence stay empty", () => {
  everyReader("moved-occurrence.ics", 2026, 10, zone, (days) => {
    assert.deepEqual(days, {
      "2026-10-05": ["09:00 Weekly"],
      "2026-10-13": ["15:00 Moved"],
      "2026-10-19": ["09:00 Weekly"],
    });
  });
});

test("a weekly 09:00 event in Berlin follows the winter and summer offset in a UTC display zone", () => {
  everyReader("zone-weekly.ics", 2026, 10, "UTC", (days) => {
    assert.deepEqual(days, {
      "2026-10-05": ["07:00 Berlin weekly"],
      "2026-10-12": ["07:00 Berlin weekly"],
      "2026-10-19": ["07:00 Berlin weekly"],
      "2026-10-26": ["08:00 Berlin weekly"],
    });
  });
});

test("a weekly Berlin event in America/Chicago shows the offset of both zones on each day", () => {
  everyReader("zone-weekly.ics", 2026, 11, "America/Chicago", (days) => {
    assert.deepEqual(days["2026-11-02"], ["02:00 Berlin weekly"]);
    assert.deepEqual(days["2026-11-30"], ["02:00 Berlin weekly"]);
  });
  everyReader("zone-weekly.ics", 2026, 10, "America/Chicago", (days) => {
    assert.deepEqual(days["2026-10-19"], ["02:00 Berlin weekly"]);
    assert.deepEqual(days["2026-10-26"], ["03:00 Berlin weekly"]);
  });
});

test("a feed with a leading byte-order mark and a feed with an invalid UTF-8 byte each give one event", () => {
  for (const [name, title] of [["byte-order-mark.ics", "With BOM"], ["invalid-utf8.ics", "Bad \ufffd byte"]]) {
    const { editable, subscribed } = readBoth(path.join(feedsDir, name));
    for (const reader of [editable, subscribed]) {
      assert.deepEqual(Object.values(reader).map((item) => item.title), [title]);
    }
  }
});

test("an alarm of 99999999999999999 weeks gives no alarm value in both readers", () => {
  const { editable, subscribed } = readBoth(path.join(feedsDir, "alarm-too-large.ics"));
  for (const reader of [editable, subscribed]) assert.equal(reader.big.alarmMinutes, null);
});
