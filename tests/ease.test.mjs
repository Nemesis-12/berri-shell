// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/Ease.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

// The 24-step search the calendar used before.
function searched(phase) {
  if (phase <= 0) return 0;
  if (phase >= 1) return 1;
  let lo = 0, hi = 1, t = phase;
  for (let i = 0; i < 24; i++) {
    const u = 1 - t;
    const bx = 3 * u * u * t * 0.4 + 3 * u * t * t * 0.2 + t * t * t;
    if (bx < phase) lo = t; else hi = t;
    t = (lo + hi) / 2;
  }
  const v = 1 - t;
  return 3 * v * t * t + t * t * t;
}

test("easeOut keeps the ends", () => {
  assert.equal(lib.easeOut(-1), 0);
  assert.equal(lib.easeOut(0), 0);
  assert.equal(lib.easeOut(1), 1);
  assert.equal(lib.easeOut(2), 1);
});

test("easeOut matches the old search", () => {
  for (let i = 1; i < 1000; i++) {
    const phase = i / 1000;
    assert.ok(Math.abs(lib.easeOut(phase) - searched(phase)) < 1e-6, "phase " + phase);
  }
});
