// Pins the open and close timelines of the pill and the picker. The expected numbers come
// from the values the panels had before they shared one slide operation (main at 9d72c9a).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function load(name, imports = {}) {
  const source = fs.readFileSync(new URL(`../logic/${name}.js`, import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, "")
    .replace(/^\.import .*$/gm, "");
  const context = vm.createContext(imports);
  vm.runInContext(source, context);
  return context;
}
const ease = load("Ease");
const timeline = load("Timeline", { Ease: ease });
const panel = load("PanelTimeline", { Timeline: timeline });

// The icon flight of the pill: start 420, fade-out start 420 + 660, 180 ms fade-out.
const flightEndMs = 420 + 660 + 180;
// Its close ends at (420 + (flightEnd - (420 + 500))) - 0.6 * 200.
const flightCloseEndMs = 420 + (flightEndMs - (420 + 500)) - 120;
// One palette strip morph: 480 ms + 5 staggers of 20 ms.
const stripSpanMs = 480 + 5 * 20;

test("pill open steps keep their lengths", () => {
  assert.deepEqual({ ...panel.pill }, { widenMs: 420, growMs: 500, shadowMs: 400, clockFadeMs: 140 });
  assert.equal(flightEndMs, 1260);
});

test("pill close steps start in the same order and end at the same time", () => {
  const close = panel.pillClose(flightEndMs, flightCloseEndMs);
  assert.deepEqual({ ...close }, {
    growCloseAtMs: 1200,
    widenCloseAtMs: 820,
    clockCloseAtMs: 568,
    closeEndMs: 484,
  });
  // The dashboard leaves first, then the pill narrows, then the clock returns.
  assert.ok(close.growCloseAtMs > close.widenCloseAtMs);
  assert.ok(close.widenCloseAtMs > close.clockCloseAtMs);
  assert.ok(close.clockCloseAtMs > close.closeEndMs);
});

test("picker open steps keep their lengths", () => {
  assert.deepEqual({ ...panel.picker }, {
    narrowMs: 420, riseMs: 480, shadowMs: 400,
    wideStartMs: 470, wideMs: 420,
    headerStartMs: 510, headerMs: 280,
    stripFadeStartMs: 790, stripFadeMs: 160,
    totalMs: 950,
  });
});

test("picker close steps start in the same order and end at the same time", () => {
  const close = panel.pickerClose(stripSpanMs);
  assert.deepEqual({ ...close }, {
    wideCloseAtMs: 910,
    narrowCloseAtMs: 591,
    stripCloseAtMs: 751,
    closeEndMs: 171,
  });
  assert.ok(close.wideCloseAtMs > close.narrowCloseAtMs);
  assert.ok(close.narrowCloseAtMs > close.closeEndMs);
});

test("a close from fully open runs to its rest time, a close from mid-way runs back to 0", () => {
  const close = panel.pillClose(flightEndMs, flightCloseEndMs);
  assert.deepEqual({ ...timeline.startClose(1, close.closeEndMs, flightEndMs) },
    { fromOpen: true, target: 484 / 1260 });
  assert.deepEqual({ ...timeline.startClose(0.5, close.closeEndMs, flightEndMs) },
    { fromOpen: false, target: 0 });
  // At full speed, the close takes the distance from 1 to the rest time.
  assert.equal(timeline.slideDurationMs(flightEndMs, 1, 484 / 1260), 776);
});
