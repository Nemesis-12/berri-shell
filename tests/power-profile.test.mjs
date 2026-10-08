import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/PowerProfileLogic.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");
const power = vm.createContext({});
vm.runInContext(source, power);

const MINUTE = 60 * 1000;

test("a side change starts the sustain window and leaves the state unchanged", () => {
  const start = { side: false, since: 0, debounced: false };
  assert.deepEqual({ ...power.sustainedSide(start, true, 1000, 2 * MINUTE) },
    { side: true, since: 1000, debounced: false });
});

test("a side that holds for the sustain window becomes the state, and a short flip back does not", () => {
  const held = { side: true, since: 1000, debounced: false };
  assert.equal(power.sustainedSide(held, true, 1000 + 2 * MINUTE, 2 * MINUTE).debounced, true);
  assert.equal(power.sustainedSide(held, true, 1000 + 2 * MINUTE - 1, 2 * MINUTE).debounced, false);
  const entered = { side: true, since: 0, debounced: true };
  const flipped = power.sustainedSide(entered, false, 5000, 2 * MINUTE);
  assert.deepEqual({ ...flipped }, { side: false, since: 5000, debounced: true });
});

test("high load wins, low load saves power only on battery, otherwise balanced", () => {
  assert.equal(power.recommendedProfile(true, true, true), "performance");
  assert.equal(power.recommendedProfile(false, true, true), "power-saver");
  assert.equal(power.recommendedProfile(false, true, false), "balanced");
  assert.equal(power.recommendedProfile(false, false, true), "balanced");
});

test("a profile switch waits for the cooldown and ignores an unchanged profile", () => {
  assert.equal(power.mayAdopt("performance", "balanced", 10 * MINUTE, 0, 10 * MINUTE), true);
  assert.equal(power.mayAdopt("performance", "balanced", 10 * MINUTE - 1, 0, 10 * MINUTE), false);
  assert.equal(power.mayAdopt("balanced", "balanced", 99 * MINUTE, 0, 10 * MINUTE), false);
});

test("the moving average covers only samples inside the window", () => {
  const old = { time: 0, load: 100 };
  const kept = power.recentSamples([old, { time: 1 * MINUTE, load: 10 }], { time: 3 * MINUTE, load: 30 }, 2 * MINUTE);
  assert.deepEqual(Array.from(kept, sample => sample.load), [10, 30]);
  assert.equal(power.averageLoad(kept), 20);
});
