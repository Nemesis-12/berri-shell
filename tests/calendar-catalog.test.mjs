import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const catalog = calendarModule("CalendarCatalog.js");
const plain = (value) => JSON.parse(JSON.stringify(value));
const dir = "/data/calendar";

test("saved calendars restore with the local one first and skip unsafe or repeated entries", () => {
  const restored = catalog.restoreCalendars(dir, { calendars: [
    { id: "berri", color: "blue", hidden: true, file: "berri.ics" },
    { id: "f-a", kind: "file", name: "Work", file: "work.ics", color: "green" },
    { id: "f-a", kind: "file", name: "Again", file: "again.ics" },
    { id: "f-b", kind: "file", name: "Escape", file: "../outside.ics" },
    { id: "l-c", kind: "link", name: "Feed", file: "subscriptions/l-c.ics", url: "https://example.test/c" },
  ] });
  assert.deepEqual(plain(restored.order), ["berri", "f-a", "l-c"]);
  assert.equal(restored.calendars.berri.color, "blue");
  assert.equal(restored.calendars.berri.hidden, true);
  assert.equal(restored.calendars["f-a"].path, dir + "/work.ics");
  assert.equal(restored.calendars["l-c"].url, "https://example.test/c");
});

test("the saved list keeps link addresses and drops empty color overrides", () => {
  const calendars = {
    berri: catalog.newMeta(dir, "berri", "local", "berri", "berri.ics", "", []),
    "l-c": { ...catalog.newMeta(dir, "l-c", "link", "Feed", "subscriptions/l-c.ics", "blue", []), url: "https://example.test/c" },
  };
  const list = plain(catalog.savedList(["berri", "l-c"], calendars));
  assert.equal(list[0].url, undefined);
  assert.equal(list[1].url, "https://example.test/c");
  assert.equal(list[1].colorOverrides, undefined);
  calendars["l-c"].colorOverrides = { u1: "#ff0000" };
  assert.deepEqual(plain(catalog.savedList(["l-c"], calendars)[0].colorOverrides), { u1: "#ff0000" });
});

test("an imported file gets a clean name that no other calendar uses", () => {
  const order = ["berri", "f-a"];
  const calendars = { berri: { file: "berri.ics" }, "f-a": { file: "Work.ics" } };
  const taken = (file) => catalog.fileTaken(order, calendars, file);
  assert.equal(catalog.importFileName("/home/u/my cal$.ics", taken), "my cal_.ics");
  assert.equal(catalog.importFileName("/home/u/work.ics", taken), "work-2.ics");
  assert.equal(catalog.importFileName("/home/u/BERRI.ics", taken), "BERRI-2.ics");
});

test("listed files are matched to calendars and missing file calendars are found", () => {
  const order = ["berri", "f-a", "l-c"];
  const calendars = {
    berri: { kind: "local", path: dir + "/berri.ics" },
    "f-a": { kind: "file", path: dir + "/a.ics" },
    "l-c": { kind: "link", path: dir + "/subscriptions/l-c.ics" },
  };
  const recordPath = (p) => p.replace(/\.ics$/, ".json");
  assert.equal(catalog.idOfPath(order, calendars, dir + "/subscriptions/l-c.json", recordPath), "l-c");
  assert.equal(catalog.idOfPath(order, calendars, dir + "/none.ics", recordPath), "");
  assert.deepEqual(plain(catalog.missingFileIds(order, calendars, [dir + "/berri.ics"])), ["f-a"]);
  assert.deepEqual(plain(catalog.newFileNames(dir, [dir + "/berri.ics", dir + "/a.ics", dir + "/new.ics"],
    (p) => p.endsWith("/a.ics"))), ["new.ics"]);
});

test("download errors name the exit code and a changed feed is told from an unchanged one", () => {
  const exits = { parserMissing: 3, notCalendar: 4, saveFailed: 5 };
  const texts = { parserMissing: "Parser is missing" };
  assert.equal(catalog.downloadError(0, exits, texts), "");
  assert.equal(catalog.downloadError(3, exits, texts), "Parser is missing");
  assert.equal(catalog.downloadError(4, exits, texts), "Not a calendar feed or parser failed");
  assert.equal(catalog.downloadError(5, exits, texts), "Could not save calendar");
  assert.notEqual(catalog.downloadError(6, exits, texts), "");
  const json = '{"records":[]}';
  const meta = { signature: catalog.recordsSignature(json), error: "", convertError: "", colorOverrides: {} };
  assert.equal(catalog.refreshResult(meta, { records: [] }, json).same, true);
  assert.equal(catalog.refreshResult({ ...meta, error: "old" }, { records: [] }, json).same, false);
  assert.equal(catalog.parseRecords("not json"), null);
  assert.equal(catalog.parseRecords('{"records":{}}'), null);
  assert.deepEqual(plain(catalog.parseRecords(json)), { records: [] });
});

test("date fields become day keys and an optional date may be empty", () => {
  const day = new Date(2026, 9, 7);
  assert.deepEqual(plain(catalog.cleanDates({ date: day, title: "x", until: "2026-10-09" })), { date: "2026-10-07", title: "x", until: "2026-10-09" });
  assert.equal(catalog.optionalKey(day), "2026-10-07");
  assert.equal(catalog.optionalKey("nope"), null);
  assert.equal(catalog.optionalKey(null), null);
  assert.equal(catalog.uniqueId({ a: 1, "a-2": 1 }, "a"), "a-3");
});

test("an item color override is set or removed on a copy", () => {
  const before = { a: "#111111" };
  assert.deepEqual(plain(catalog.withItemColor(before, "b", "#222222")), { a: "#111111", b: "#222222" });
  assert.deepEqual(plain(catalog.withItemColor(before, "a", "")), {});
  assert.deepEqual(plain(before), { a: "#111111" });
});
