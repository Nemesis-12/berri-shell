// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/ShownRows.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

// Same calls as a QML ListModel, with a log of the changes.
function fakeRows(initial) {
  const items = initial.map((x) => ({ ...x }));
  const log = [];
  return {
    items,
    log,
    get count() { return items.length; },
    get: (i) => items[i],
    remove: (i) => { log.push("remove " + i); items.splice(i, 1); },
    insert: (i, e) => { log.push("insert " + i); items.splice(i, 0, { ...e }); },
    move: (from, to) => { log.push("move " + from + ">" + to); items.splice(to, 0, items.splice(from, 1)[0]); },
    setProperty: (i, f, v) => { log.push("set " + i + "." + f); items[i][f] = v; },
  };
}

test("removes, inserts and keeps the wanted order", () => {
  const rows = fakeRows([{ key: "a", n: 1 }, { key: "b", n: 2 }, { key: "c", n: 3 }]);
  lib.matchRows(rows, [{ key: "c", n: 3 }, { key: "a", n: 1 }, { key: "d", n: 4 }]);
  assert.deepEqual(rows.items.map((x) => x.key), ["c", "a", "d"]);
  assert.deepEqual(rows.log, ["remove 1", "move 1>0", "insert 2"]);
});

test("changes only the fields that differ", () => {
  const rows = fakeRows([{ key: "a", n: 1, t: "x" }]);
  lib.matchRows(rows, [{ key: "a", n: 2, t: "x" }]);
  assert.deepEqual(rows.log, ["set 0.n"]);
});

test("uses the calendar ID to keep rows when their names change", () => {
  const rows = fakeRows([{ calId: "p", name: "A" }, { calId: "q", name: "B" }]);
  const keptCalendar = rows.get(1);
  lib.matchRows(rows, [{ calId: "q", name: "B2" }, { calId: "r", name: "C" }], "calId");
  assert.equal(rows.get(0), keptCalendar);
  assert.deepEqual(rows.items, [{ calId: "q", name: "B2" }, { calId: "r", name: "C" }]);
});
