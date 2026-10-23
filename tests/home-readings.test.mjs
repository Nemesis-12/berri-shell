import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const readings = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/HomeReadings.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), readings);

test("a battery cell exists only for a present battery", () => {
  assert.equal(readings.hasBattery(null), false);
  assert.equal(readings.hasBattery({ isPresent: false, percentage: 0 }), false);
  assert.equal(readings.hasBattery({ ready: false, isLaptopBattery: true, isPresent: true }), false);
  assert.equal(readings.hasBattery({ ready: true, isLaptopBattery: false, isPresent: true }), false);
  assert.equal(readings.hasBattery({ ready: true, isLaptopBattery: true, isPresent: false }), false);
  assert.equal(readings.hasBattery({ ready: true, isLaptopBattery: true, isPresent: true, percentage: 0.42 }), true);
});
