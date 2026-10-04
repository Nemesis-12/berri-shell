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
  const out = path.join(scratch, `${path.basename(file)}.json`);
  const run = spawnSync(converter, [file, out], { env: { ...process.env, TZ: zone }, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const subscribed = JSON.parse(fs.readFileSync(out, "utf8")).records.map(Format.expandCompactItem);
  const editable = Format.readCalendar(fs.readFileSync(file, "utf8")).items;
  const byUid = (items) => Object.fromEntries(items.map((item) => [item.uid, withoutSourceText(item)]));
  return { editable: byUid(editable), subscribed: byUid(subscribed) };
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
