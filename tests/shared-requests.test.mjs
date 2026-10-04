// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function load(name) {
  const source = fs.readFileSync(new URL(`../logic/${name}.js`, import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, "");
  const lib = vm.createContext({ Map, Math });
  vm.runInContext(source, lib);
  return lib;
}

test("a shared thing stays on until the last owner lets go", () => {
  const { create, acquire, release } = load("RequestCounts");
  const table = create();
  const adapter = {};
  const other = {};
  assert.equal(acquire(table, adapter), 1);
  assert.equal(acquire(table, adapter), 2);
  assert.equal(acquire(table, other), 1);
  assert.equal(release(table, adapter), 1);
  assert.equal(release(table, other), 0);
  assert.equal(release(table, adapter), 0);
});

test("an extra release never makes the count negative", () => {
  const { create, acquire, release } = load("RequestCounts");
  const table = create();
  const key = {};
  assert.equal(release(table, key), 0);
  assert.equal(acquire(table, key), 1);
});

test("sameItems compares identity and order", () => {
  const { sameItems } = load("ListSync");
  const a = {}, b = {};
  assert.equal(sameItems([a, b], [a, b]), true);
  assert.equal(sameItems([a, b], [b, a]), false);
  assert.equal(sameItems([a], [a, b]), false);
  assert.equal(sameItems([], []), true);
  assert.equal(sameItems([{}], [{}]), false);
});
