// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const easeSource = fs.readFileSync(new URL("../logic/Ease.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const ease = vm.createContext({});
vm.runInContext(easeSource, ease);
const source = fs.readFileSync(new URL("../logic/Timeline.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "")
  .replace(/^\.import "Ease.js" as Ease.*$/m, "");
const lib = vm.createContext({ Ease: ease });
vm.runInContext(source, lib);

// Qt's own way: search the bezier's x(t) for the phase.
function searched(phase) {
  let lo = 0, hi = 1, t = phase;
  for (let i = 0; i < 40; i++) {
    const u = 1 - t;
    const bx = 3 * u * u * t * 0.32 + t * t * t;
    if (bx < phase) lo = t; else hi = t;
    t = (lo + hi) / 2;
  }
  const u = 1 - t;
  return 3 * u * u * t * 0.72 + 3 * u * t * t + t * t * t;
}

test("slice is 0 before the window, 1 after it, and straight inside", () => {
  assert.equal(lib.slice(50, 100, 200), 0);
  assert.equal(lib.slice(100, 100, 200), 0);
  assert.equal(lib.slice(200, 100, 200), 0.5);
  assert.equal(lib.slice(300, 100, 200), 1);
  assert.equal(lib.slice(999, 100, 200), 1);
});

test("spring keeps the ends", () => {
  assert.equal(ease.spring(-1), 0);
  assert.equal(ease.spring(0), 0);
  assert.equal(ease.spring(1), 1);
  assert.equal(ease.spring(2), 1);
});

test("spring matches the bezier curve", () => {
  for (let i = 1; i < 1000; i++) {
    const phase = i / 1000;
    assert.ok(Math.abs(ease.spring(phase) - searched(phase)) < 1e-6, "phase " + phase);
  }
});

test("springSlice runs spring over one window", () => {
  assert.equal(lib.springSlice(0, 100, 200), 0);
  assert.equal(lib.springSlice(400, 100, 200), 1);
  assert.equal(lib.springSlice(200, 100, 200), ease.spring(0.5));
});

test("closing springSlice leaves fast and settles slowly", () => {
  assert.equal(lib.springSlice(400, 100, 200, true), 1);
  assert.equal(lib.springSlice(100, 100, 200, true), 0);
  assert.equal(lib.springSlice(400, 100, 200, false), 1);
  // Close goes from phase 1 to 0. The first step down is large, the last is small.
  const first = 1 - lib.springSlice(300 - 2, 100, 200, true);
  const last = lib.springSlice(100 + 2, 100, 200, true);
  assert.ok(first > 5 * last, "first " + first + " last " + last);
});

test("closing is the open curve mirrored, so open and close agree at every phase", () => {
  for (let i = 0; i <= 100; i++) {
    const phase = i / 100;
    const at = 100 + phase * 200;
    assert.ok(Math.abs(lib.springSlice(at, 100, 200, true) - (1 - ease.spring(1 - phase))) < 1e-12);
  }
});

test("fadeSlice is straight opening and settles slowly closing", () => {
  assert.equal(lib.fadeSlice(200, 100, 200, false), 0.5);
  assert.equal(lib.fadeSlice(100, 100, 200, true), 0);
  assert.equal(lib.fadeSlice(300, 100, 200, true), 1);
  // Slope at the rest end (phase 0) of the close is near 0; at the start (phase 1) it is steep.
  const atRest = lib.fadeSlice(100 + 1, 100, 200, true);
  const atStart = 1 - lib.fadeSlice(300 - 1, 100, 200, true);
  assert.ok(atStart > 5 * atRest);
});

test("closing window ends at closeAtMs and keeps its length", () => {
  // Window 100..300 closes over 500..700: the part is at rest before 500, in place from 700.
  assert.equal(lib.springSlice(500, 100, 200, true, 700), 0);
  assert.equal(lib.springSlice(700, 100, 200, true, 700), 1);
  assert.equal(lib.fadeSlice(300, 100, 200, true, 700), 0);
  assert.equal(lib.fadeSlice(1000, 100, 200, true, 700), 1);
  // The open values do not depend on closeAtMs.
  assert.equal(lib.springSlice(200, 100, 200, false, 700), ease.spring(0.5));
  assert.equal(lib.fadeSlice(200, 100, 200, false, 700), 0.5);
});
