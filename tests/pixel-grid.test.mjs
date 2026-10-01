// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/PixelGrid.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

test("dpr falls back to 1", () => {
  assert.equal(lib.dpr(2), 2);
  assert.equal(lib.dpr(0), 1);
  assert.equal(lib.dpr(undefined), 1);
});

test("snap rounds to device pixels", () => {
  assert.equal(lib.snap(10.3, 2), 10.5);
  assert.equal(lib.snap(10.2, 2), 10);
  assert.equal(lib.snap(10.6, 1), 11);
  assert.equal(lib.snap(10.6, 0), 11);
});
