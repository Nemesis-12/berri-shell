import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const Items = calendarModule("CalendarItems.js");
const Months = calendarModule("CalendarMonths.js");
const plain = value => JSON.parse(JSON.stringify(value));
const item = fields => Items.makeItem({ uid: "edited", title: "Before", date: "2026-10-05", ...fields });
const calendar = (items, fields = {}) => ({ id: "berri", name: "berri", kind: "local",
  color: "accent", hidden: false, document: { items }, ...fields });

test("one item edit keeps other months cached and leaves their views unchanged", () => {
  const local = calendar([item({}), item({ uid: "other", title: "Other", date: "2026-11-05" })]);
  const months = Months.createMonthCache([local]);
  const september = Months.cachedItemsInMonth(months, 2026, 9);
  const october = Months.cachedItemsInMonth(months, 2026, 10);
  const november = Months.cachedItemsInMonth(months, 2026, 11);
  const before = plain(november);
  local.document.items[0] = Items.applyChanges(local.document.items[0], { title: "After" });
  Months.editMonthCache(months, local, ["edited"]);
  assert.strictEqual(Months.cachedItemsInMonth(months, 2026, 9), september);
  assert.strictEqual(Months.cachedItemsInMonth(months, 2026, 11), november);
  assert.deepEqual(plain(november), before);
  assert.notStrictEqual(Months.cachedItemsInMonth(months, 2026, 10), october);
  assert.equal(Months.cachedItemsInMonth(months, 2026, 10)["2026-10-05"][0].title, "After");
});

test("editing the later duplicate's title separates its copy and changing it back joins the first copy", () => {
  const b = calendar([item({ uid: "b-event" })], { id: "b", name: "B", kind: "file" });
  const a = calendar([item({ uid: "a-event" })], { id: "a", name: "A", kind: "file" });
  const months = Months.createMonthCache([b, a]);
  const shown = () => plain(Months.cachedItemsInMonth(months, 2026, 10)["2026-10-05"]
    .map(o => ({ calendarId: o.calendarId, sourceUid: o.sourceUid, title: o.title, alsoIn: o.alsoIn })));
  assert.deepEqual(shown(), [{ calendarId: "b", sourceUid: "b-event", title: "Before", alsoIn: ["A"] }]);

  a.document.items[0] = Items.applyChanges(a.document.items[0], { title: "After" });
  Months.editMonthCache(months, a, ["a-event"]);
  assert.deepEqual(shown(), [
    { calendarId: "a", sourceUid: "a-event", title: "After", alsoIn: [] },
    { calendarId: "b", sourceUid: "b-event", title: "Before", alsoIn: [] }
  ]);

  a.document.items[0] = Items.applyChanges(a.document.items[0], { title: "Before" });
  Months.editMonthCache(months, a, ["a-event"]);
  assert.deepEqual(shown(), [{ calendarId: "b", sourceUid: "b-event", title: "Before", alsoIn: ["A"] }]);
});

test("selective edits keep the eight-month cache limit and drop the month asked for longest ago", () => {
  const local = calendar([item({})]);
  const months = Months.createMonthCache([local]);
  const read = (year, month) => Months.cachedItemsInMonth(months, year, month);
  const september = read(2026, 9);
  read(2026, 10);
  const november = read(2026, 11);
  read(2026, 12);
  for (const month of [1, 2, 3, 4]) read(2027, month);
  local.document.items[0] = Items.applyChanges(local.document.items[0], { title: "After" });
  Months.editMonthCache(months, local, ["edited"]);
  assert.strictEqual(read(2026, 9), september);
  assert.equal(read(2026, 10)["2026-10-05"][0].title, "After");
  // Eight months are cached. A ninth evicts the one asked for longest ago, not the ones read again just now.
  read(2027, 5);
  assert.strictEqual(read(2026, 9), september);
  assert.notStrictEqual(read(2026, 11), november);
});

test("a month that is read again stays cached when new months arrive", () => {
  const months = Months.createMonthCache([calendar([item({})])]);
  const first = Months.cachedItemsInMonth(months, 2026, 1);
  for (let month = 2; month <= 12; month++) {
    Months.cachedItemsInMonth(months, 2026, month);
    assert.strictEqual(Months.cachedItemsInMonth(months, 2026, 1), first);
  }
  assert.equal(months.builds, 12);
});

test("two loaded grid pages three months apart and the selected month fit the cache without a repeated build", () => {
  const months = Months.createMonthCache([calendar([item({})])]);
  const page = first => [first, first + 1, first + 2].forEach(month => Months.cachedItemsInMonth(months, 2026, month));
  page(1);
  page(4);
  Months.cachedItemsInMonth(months, 2026, 10);
  assert.equal(months.builds, 7);
  // A page change back and forth builds nothing more.
  page(1);
  page(4);
  Months.cachedItemsInMonth(months, 2026, 10);
  page(1);
  assert.equal(months.builds, 7);
});

test("neighbour pages share months, so a page change builds only the new month", () => {
  const months = Months.createMonthCache([calendar([item({})])]);
  const page = first => [first, first + 1, first + 2].forEach(month => Months.cachedItemsInMonth(months, 2026, month));
  page(8);
  page(9);
  assert.equal(months.builds, 4);
});

test("a subscription row refresh keeps cached months and shows the new update time", () => {
  const feed = { id: "f", name: "Feed", kind: "link", color: "blue", hidden: false, url: "https://example.test/f",
    file: "f.ics", updatedAt: 1, records: [{ uid: "r", kind: "event", title: "Rec", date: "2026-10-05", repeat: "none", time: null }] };
  const months = Months.createMonthCache([feed]);
  const october = Months.cachedItemsInMonth(months, 2026, 10);
  assert.equal(months.builds, 1);
  Months.refreshCalendarRow(months, { ...feed, updatedAt: 99 });
  assert.equal(months.projection.calendars[0].updatedAt, 99);
  assert.strictEqual(Months.cachedItemsInMonth(months, 2026, 10), october);
  assert.equal(months.builds, 1);
});
