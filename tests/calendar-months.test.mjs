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

test("selective edits keep the three-month cache limit", () => {
  const local = calendar([item({})]);
  const months = Months.createMonthCache([local]);
  const september = Months.cachedItemsInMonth(months, 2026, 9);
  Months.cachedItemsInMonth(months, 2026, 10);
  const november = Months.cachedItemsInMonth(months, 2026, 11);
  local.document.items[0] = Items.applyChanges(local.document.items[0], { title: "After" });
  Months.editMonthCache(months, local, ["edited"]);
  assert.strictEqual(Months.cachedItemsInMonth(months, 2026, 9), september);
  assert.equal(Months.cachedItemsInMonth(months, 2026, 10)["2026-10-05"][0].title, "After");
  Months.cachedItemsInMonth(months, 2026, 12);
  assert.strictEqual(Months.cachedItemsInMonth(months, 2026, 11), november);
  assert.notStrictEqual(Months.cachedItemsInMonth(months, 2026, 9), september);
  assert.deepEqual(plain(Months.cachedItemsInMonth(months, 2026, 9)), {});
});
