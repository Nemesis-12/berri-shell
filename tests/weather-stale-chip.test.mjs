// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const load = (name, context) => vm.runInContext(
  fs.readFileSync(new URL(`../logic/${name}.js`, import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, "").replace(/^\.import .*$/gm, ""), context);
const times = vm.createContext({});
load("Times", times);
const format = vm.createContext({ Times: times });
load("WeatherFormat", format);

const NOW = Date.UTC(2026, 9, 4, 12, 0, 0);
const MIN = 60000;

test("the chip says NO DATA before the first good reading", () => {
  assert.equal(format.staleChip(0, NOW), "NO DATA");
});

test("the chip shows the age of the last good reading", () => {
  assert.equal(format.staleChip(NOW - 20000, NOW), "JUST NOW");
  assert.equal(format.staleChip(NOW - 5 * MIN, NOW), "5 M AGO");
  assert.equal(format.staleChip(NOW - 120 * MIN, NOW), "2 H AGO");
  assert.equal(format.staleChip(NOW - 3 * 1440 * MIN, NOW), "3 D AGO");
});

test("the age grows as the clock moves on", () => {
  const stamp = NOW - 59 * MIN;
  assert.equal(format.staleChip(stamp, NOW), "59 M AGO");
  assert.equal(format.staleChip(stamp, NOW + MIN), "1 H AGO");
});
