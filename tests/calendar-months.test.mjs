import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { calendarCode } from "./fixtures/calendar-code.mjs";

const ics = calendarCode();
const save = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/CalendarSave.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), save);
const plain = value => JSON.parse(JSON.stringify(value));
const item = fields => ics.makeItem({ uid: "edited", title: "Before", date: "2026-10-05", ...fields });
const calendar = (items, fields = {}) => ({ id: "berri", name: "berri", kind: "local",
  color: "accent", hidden: false, document: { items }, ...fields });

// Execute the service's functions. Only file writes, saved settings and signals are test boundaries.
function service(items, extras = []) {
  const local = calendar(items, { path: "/copy/berri.ics", file: "berri.ics" });
  local.document = { ...ics.emptyCalendar(), items };
  local.text = ics.writeCalendar(local.document);
  const lib = vm.createContext({ Ics: ics, Save: save,
    dir: "/copy", defaultPath: local.path, revision: 0, lastError: "", failed: "", failWrite: false,
    ready: false, _stateRead: false,
    _calendars: Object.fromEntries([local, ...extras].map(cal => [cal.id, cal])),
    _order: [local, ...extras].map(cal => cal.id),
    savedCalendars: { save() {} } });
  lib.root = lib;
  lib.saveFailed = message => { lib.failed = message; };
  lib.files = { write(path, text, report) { report(!lib.failWrite, lib.failWrite ? "Permission denied" : ""); },
    recordPath: path => path.replace(/\.ics$/, ".json") };
  const qml = fs.readFileSync(new URL("../services/Calendar.qml", import.meta.url), "utf8");
  for (const [, name, params, body] of qml.matchAll(/^    function (\w+)\((.*?)\): \w+ \{([\s\S]*?)^    \}/gm)) {
    const args = params.replace(/: \w+/g, "");
    vm.runInContext(`function ${name}(${args}) {${body}\n}`, lib);
  }
  lib._rebuild();
  return lib;
}

test("one item edit keeps other months cached and leaves their views unchanged", () => {
  const local = calendar([item({}), item({ uid: "other", title: "Other", date: "2026-11-05" })]);
  const months = ics.createMonthCache([local]);
  const september = ics.cachedItemsInMonth(months, 2026, 9);
  const october = ics.cachedItemsInMonth(months, 2026, 10);
  const november = ics.cachedItemsInMonth(months, 2026, 11);
  const before = plain(november);
  local.document.items[0] = ics.applyChanges(local.document.items[0], { title: "After" });
  ics.editMonthCache(months, local, ["edited"]);
  assert.strictEqual(ics.cachedItemsInMonth(months, 2026, 9), september);
  assert.strictEqual(ics.cachedItemsInMonth(months, 2026, 11), november);
  assert.deepEqual(plain(november), before);
  assert.notStrictEqual(ics.cachedItemsInMonth(months, 2026, 10), october);
  assert.equal(ics.cachedItemsInMonth(months, 2026, 10)["2026-10-05"][0].title, "After");
});

test("the service save updates the edited month and retains the other month objects", () => {
  const shell = service([item({})]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { title: "Saved" }), true);
  assert.strictEqual(shell.itemsInMonth(2026, 9), september);
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.equal(shell.itemsOn("2026-10-05")[0].title, "Saved");
  assert.equal(ics.readCalendar(shell._calendars.berri.text).items[0].title, "Saved");
});

test("an unbounded repeat edit updates every cached occurrence month but keeps earlier months", () => {
  const shell = service([item({ date: "2026-10-05", repeat: "monthly" })]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  const future = shell.itemsInMonth(2036, 10);
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { title: "Series" }), true);
  assert.strictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.notStrictEqual(shell.itemsInMonth(2036, 10), future);
  assert.equal(shell.itemsOn("2026-10-05")[0].title, "Series");
  assert.equal(shell.itemsOn("2036-10-05")[0].title, "Series");
});

test("a repeat rule change clears old and new occurrence months and keeps gaps cached", () => {
  const shell = service([item({ date: "2026-01-05", repeat: "monthly", count: 2 })]);
  const february = shell.itemsInMonth(2026, 2);
  const march = shell.itemsInMonth(2026, 3);
  const nextYear = shell.itemsInMonth(2027, 1);
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { repeat: "yearly" }), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 2), february);
  assert.deepEqual(plain(shell.itemsInMonth(2026, 2)), {});
  assert.strictEqual(shell.itemsInMonth(2026, 3), march);
  assert.notStrictEqual(shell.itemsInMonth(2027, 1), nextYear);
  assert.equal(shell.itemsOn("2027-01-05")[0].title, "Before");
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { repeat: "none" }), true);
  assert.deepEqual(plain(shell.itemsInMonth(2027, 1)), {});
  assert.equal(shell.itemsOn("2026-01-05")[0].recurring, false);
});

test("moving a single item clears its old and new months and keeps the month between them", () => {
  const shell = service([item({ date: "2026-09-05" })]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  assert.equal(shell.move(ics.itemKey("berri", "edited"), "2026-09-05", "2026-11-05", {}), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.deepEqual(plain(shell.itemsInMonth(2026, 9)), {});
  assert.strictEqual(shell.itemsInMonth(2026, 10), october);
  assert.notStrictEqual(shell.itemsInMonth(2026, 11), november);
  assert.equal(shell.itemsOn("2026-11-05")[0].occurrenceDate, "2026-11-05");
});

test("moving one repeat occurrence updates both spans and keeps the remaining series cached", () => {
  const shell = service([item({ date: "2026-09-30", endDate: "2026-10-02", repeat: "monthly" })]);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  const december = shell.itemsInMonth(2026, 12);
  assert.equal(shell.move(ics.itemKey("berri", "edited"), "2026-09-30", "2026-12-30", {}), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.deepEqual(plain(shell.itemsOn("2026-10-01")), []);
  assert.equal(shell.itemsOn("2026-10-30")[0].recurring, true);
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
  assert.equal(november["2026-11-01"][0].occurrenceDate, "2026-10-30");
  assert.notStrictEqual(shell.itemsInMonth(2026, 12), december);
  assert.deepEqual(plain(shell.itemsOn("2026-12-30").map(o => o.recurring)), [true, false]);
  assert.equal(shell.itemsOn("2027-01-01").some(o => o.occurrenceDate === "2026-12-30" && !o.recurring), true);
});

test("a repeat delete clears its occurrence months, including a final multi-day span", () => {
  const shell = service([item({ date: "2026-09-29", endDate: "2026-10-02", repeat: "daily", until: "2026-09-30" })]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  assert.equal(shell.remove(ics.itemKey("berri", "edited")), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
  assert.deepEqual(plain(shell.itemsInMonth(2026, 10)), {});
  assert.equal(shell.add({ date: "2026-10-08", title: "Added" }), true);
  assert.equal(shell.itemsOn("2026-10-08")[0].title, "Added");
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
});

test("ticking or deleting one repeat occurrence keeps its other occurrence months cached", () => {
  const shell = service([item({ repeat: "monthly" })]);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  const december = shell.itemsInMonth(2026, 12);
  const uid = ics.itemKey("berri", "edited");
  assert.equal(shell.setDone(uid, true, "2026-10-05"), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.equal(shell.itemsOn("2026-10-05")[0].done, true);
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
  assert.equal(november["2026-11-05"][0].done, false);
  assert.equal(shell.remove(uid, "2026-10-05"), true);
  assert.deepEqual(plain(shell.itemsOn("2026-10-05")), []);
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
  assert.strictEqual(shell.itemsInMonth(2026, 12), december);
});

test("COUNT and a skipped monthly date limit the months affected by a series edit", () => {
  const shell = service([item({ date: "2026-01-31", repeat: "monthly", count: 2 })]);
  const february = shell.itemsInMonth(2026, 2);
  const march = shell.itemsInMonth(2026, 3);
  const april = shell.itemsInMonth(2026, 4);
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { title: "Limited" }), true);
  assert.strictEqual(shell.itemsInMonth(2026, 2), february);
  assert.notStrictEqual(shell.itemsInMonth(2026, 3), march);
  assert.equal(shell.itemsOn("2026-03-31")[0].title, "Limited");
  assert.strictEqual(shell.itemsInMonth(2026, 4), april);
  assert.deepEqual(plain(april), {});
});

test("shortening UNTIL clears a final span without rebuilding earlier unchanged months", () => {
  const shell = service([item({ date: "2026-09-29", endDate: "2026-10-02", repeat: "daily", until: "2026-09-30" })]);
  const august = shell.itemsInMonth(2026, 8);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { until: "2026-09-29" }), true);
  assert.strictEqual(shell.itemsInMonth(2026, 8), august);
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.deepEqual(plain(shell.itemsOn("2026-10-02").map(o => o.occurrenceDate)), ["2026-09-29"]);
  assert.deepEqual(plain(shell.itemsOn("2026-10-03")), []);
});

test("a link item's own color changes the kept duplicate in every affected month", () => {
  const repeated = item({ repeat: "monthly" });
  const feed = { id: "feed", name: "Feed", kind: "link", color: "blue", hidden: false,
    records: [plain(repeated)], colorOverrides: {} };
  const shell = service([repeated], [feed]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  assert.equal(october["2026-10-05"][0].calendarId, "berri");
  assert.equal(shell.setItemColor(ics.itemKey("feed", "edited"), "red"), true);
  assert.strictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.notStrictEqual(shell.itemsInMonth(2026, 11), november);
  const shown = shell.itemsOn("2026-11-05");
  assert.equal(shown.length, 1);
  assert.equal(shown[0].calendarId, "feed");
  assert.equal(shown[0].color, "red");
  assert.deepEqual(plain(shown[0].alsoInIds), ["berri"]);
  assert.equal(shell.setItemColor(ics.itemKey("feed", "edited"), null), true);
  assert.equal(shell.itemsOn("2026-11-05")[0].calendarId, "berri");
});

test("a failed item save restores the item and retains unchanged cached views", () => {
  const shell = service([item({ repeat: "monthly" })]);
  const october = shell.itemsInMonth(2026, 10);
  const november = shell.itemsInMonth(2026, 11);
  shell.failWrite = true;
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { date: "2027-01-05", title: "Lost" }), false);
  assert.strictEqual(shell.itemsInMonth(2026, 10), october);
  assert.strictEqual(shell.itemsInMonth(2026, 11), november);
  assert.equal(shell.getItem(ics.itemKey("berri", "edited")).title, "Before");
  assert.equal(shell.failed, "Could not save berri: Permission denied");
  assert.equal(shell.lastError, shell.failed);
});

test("a file import keeps the full rebuild and exposes the imported month", () => {
  const shell = service([item({})]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  shell.files.readNow = () => ics.writeCalendar({ ...ics.emptyCalendar(),
    items: [item({ uid: "imported", date: "2026-09-12", title: "Imported" })] });
  const id = shell.importFile("/outside/copied.ics", "blue");
  assert.notEqual(id, "");
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.equal(shell.itemsOn("2026-09-12")[0].title, "Imported");
  assert.equal(shell.itemsOn("2026-09-12")[0].calendarId, id);
});

test("calendar-wide color and visibility settings keep the full rebuild", () => {
  const shell = service([item({})]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  shell.setCalendarColor("berri", "green");
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.equal(shell.itemsOn("2026-10-05")[0].color, "green");
  const colored = shell.itemsInMonth(2026, 10);
  shell.setCalendarHidden("berri", true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), colored);
  assert.deepEqual(plain(shell.itemsOn("2026-10-05")), []);
  shell.setCalendarHidden("berri", false);
  assert.equal(shell.itemsOn("2026-10-05")[0].color, "green");
});

test("moving a whole repeat series to a new start clears its old and new ranges", () => {
  const shell = service([item({ date: "2026-09-05", repeat: "monthly", count: 2 })]);
  const september = shell.itemsInMonth(2026, 9);
  const december = shell.itemsInMonth(2026, 12);
  const february = shell.itemsInMonth(2027, 2);
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { date: "2026-12-05" }), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.deepEqual(plain(shell.itemsInMonth(2026, 9)), {});
  assert.notStrictEqual(shell.itemsInMonth(2026, 12), december);
  assert.equal(shell.itemsOn("2026-12-05")[0].title, "Before");
  assert.strictEqual(shell.itemsInMonth(2027, 2), february);
  assert.deepEqual(plain(shell.itemsOn("2026-10-05")), []);
  assert.equal(shell.itemsOn("2027-01-05")[0].title, "Before");
});

test("item edits update reminder inputs and leave other calendars' month inputs shared", () => {
  const second = calendar([item({ uid: "second", kind: "reminder", title: "Second" })],
    { id: "second", name: "Second", kind: "file", path: "/copy/second.ics", file: "second.ics" });
  const shell = service([item({ kind: "reminder", title: "First" })], [second]);
  const source = shell._months.projection.sources[1];
  const row = shell._months.projection.calendars[1];
  assert.equal(shell.update(ics.itemKey("berri", "edited"), { title: "Changed", time: "10:00" }), true);
  assert.deepEqual(plain(shell.allItems().map(it => [it.title, it.time])), [["Changed", "10:00"], ["Second", "09:00"]]);
  assert.strictEqual(shell._months.projection.sources[1], source);
  assert.strictEqual(shell._months.projection.calendars[1], row);
  assert.equal(shell.add({ kind: "reminder", date: "2026-10-08", title: "New" }), true);
  assert.equal(shell._months.projection.calendars[0].itemCount, 2);
  assert.equal(shell.allItems().length, 3);
});

test("outside file changes and bulk item colors clear all month caches", () => {
  const second = calendar([item({ color: "red" })],
    { id: "second", name: "Second", kind: "file", path: "/copy/second.ics", file: "second.ics" });
  second.document = { ...ics.emptyCalendar(), items: second.document.items };
  second.text = ics.writeCalendar(second.document);
  const shell = service([], [second]);
  const september = shell.itemsInMonth(2026, 9);
  const october = shell.itemsInMonth(2026, 10);
  assert.equal(shell.applyColorToCalendar("second", "blue"), true);
  assert.notStrictEqual(shell.itemsInMonth(2026, 9), september);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), october);
  assert.equal(shell.itemsOn("2026-10-05")[0].color, "blue");
  const colored = shell.itemsInMonth(2026, 10);
  shell._ingest("/copy/second.ics", ics.writeCalendar({ ...ics.emptyCalendar(),
    items: [item({ date: "2026-10-05", title: "Outside" })] }), false);
  assert.notStrictEqual(shell.itemsInMonth(2026, 10), colored);
  assert.equal(shell.itemsOn("2026-10-05")[0].title, "Outside");
});

test("selective edits keep the three-month cache limit", () => {
  const local = calendar([item({})]);
  const months = ics.createMonthCache([local]);
  const september = ics.cachedItemsInMonth(months, 2026, 9);
  ics.cachedItemsInMonth(months, 2026, 10);
  const november = ics.cachedItemsInMonth(months, 2026, 11);
  local.document.items[0] = ics.applyChanges(local.document.items[0], { title: "After" });
  ics.editMonthCache(months, local, ["edited"]);
  assert.strictEqual(ics.cachedItemsInMonth(months, 2026, 9), september);
  assert.equal(ics.cachedItemsInMonth(months, 2026, 10)["2026-10-05"][0].title, "After");
  ics.cachedItemsInMonth(months, 2026, 12);
  assert.strictEqual(ics.cachedItemsInMonth(months, 2026, 11), november);
  assert.notStrictEqual(ics.cachedItemsInMonth(months, 2026, 9), september);
  assert.deepEqual(plain(ics.cachedItemsInMonth(months, 2026, 9)), {});
});
