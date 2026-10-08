// Run: node --test tests/sticker-size.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const lib = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/StickerSize.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), lib);

test("at scale 1 the sticker uses one image pixel per logical pixel", () => {
  assert.deepEqual({ ...lib.pixelSize(250, 300, 1) }, { width: 250, height: 300 });
});

test("at scale 2 the sticker uses two image pixels per logical pixel", () => {
  assert.deepEqual({ ...lib.pixelSize(250, 300, 2) }, { width: 500, height: 600 });
});

test("a fractional size rounds to whole pixels and never goes under 1", () => {
  assert.deepEqual({ ...lib.pixelSize(250.4, 100.6, 1.5) }, { width: 376, height: 151 });
  assert.deepEqual({ ...lib.pixelSize(0, 0, 2) }, { width: 1, height: 1 });
  assert.equal(lib.hasSize(0, 10), false);
  assert.equal(lib.hasSize(250, 10), true);
});
