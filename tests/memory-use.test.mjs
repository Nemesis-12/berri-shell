// Run: node --test berri-shell/tests/memory-use.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs
  .readFileSync(new URL("../logic/MemoryUse.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

const sample = [
  "MemTotal:       16777216 kB",
  "MemFree:         1000000 kB",
  "MemAvailable:    8388608 kB",
  "SwapTotal:       4194304 kB",
  "SwapFree:        3145728 kB",
].join("\n");

test("reads used memory, percent and swap", () => {
  const memoryUse = lib.readMemoryUse(sample);
  assert.equal(memoryUse.totalGb, 16);
  assert.equal(memoryUse.usedGb, 8);
  assert.equal(memoryUse.percent, 50);
  assert.equal(memoryUse.swapTotalGb, 4);
  assert.equal(memoryUse.swapUsedGb, 1);
});

test("returns null without MemAvailable", () => {
  assert.equal(lib.readMemoryUse("MemTotal: 100 kB\nMemFree: 50 kB"), null);
});

test("a machine without swap gives zero swap", () => {
  const memoryUse = lib.readMemoryUse("MemTotal: 2097152 kB\nMemAvailable: 1048576 kB");
  assert.equal(memoryUse.swapTotalGb, 0);
  assert.equal(memoryUse.swapUsedGb, 0);
});
