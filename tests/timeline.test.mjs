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

test("closing is the open curve mirrored over the shorter close window", () => {
  const closeMs = 300 - lib.closeEnd(300, 200);
  for (let i = 0; i <= 100; i++) {
    const phase = i / 100;
    const at = 300 - closeMs + phase * closeMs;
    assert.ok(Math.abs(lib.springSlice(at, 100, 200, true) - (1 - ease.spring(1 - phase))) < 1e-12);
  }
});

test("a closing part is within 1 px of rest at the end of its close window, even for 300 px of travel", () => {
  const closeMs = 500 - lib.closeEnd(500, 500);
  assert.ok(closeMs < 500);
  assert.equal(lib.springSlice(lib.closeEnd(500, 500), 0, 500, true, 500), 0);
  // 1 ms before the end of the window, 300 px of travel is left over by under 1 px.
  assert.ok(300 * lib.springSlice(500 - closeMs + 1, 0, 500, true, 500) < 1);
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

test("closing window ends at closeAtMs and is closeShare of the open window long", () => {
  // Window 100..300 closes over closeEnd(700, 200)..700: at rest before that, in place from 700.
  assert.equal(lib.springSlice(lib.closeEnd(700, 200), 100, 200, true, 700), 0);
  assert.equal(lib.springSlice(700, 100, 200, true, 700), 1);
  assert.equal(lib.fadeSlice(300, 100, 200, true, 700), 0);
  assert.equal(lib.fadeSlice(1000, 100, 200, true, 700), 1);
  // The open values do not depend on closeAtMs.
  assert.equal(lib.springSlice(200, 100, 200, false, 700), ease.spring(0.5));
  assert.equal(lib.fadeSlice(200, 100, 200, false, 700), 0.5);
});

// The real close of the notch (picker/ThemeNotch.qml) and the pill (pill/Pill.qml):
// at the elapsed time where the close is cut, every size is within 1 px of rest.
test("the notch close ends within 1 px of rest", () => {
  const riseMs = 480, narrowMs = 420, wideStartMs = 470, wideMs = 420;
  const totalMs = wideStartMs + 40 + 280 + 160;
  const wideCloseAtMs = totalMs - 40;
  const narrowCloseAtMs = wideCloseAtMs - Math.round(wideMs * 0.76);
  const stripTermMs = narrowCloseAtMs - narrowMs;
  const cutMs = Math.min(lib.closeEnd(narrowCloseAtMs, riseMs), lib.closeEnd(narrowCloseAtMs, narrowMs), stripTermMs);
  const left = (travel, startMs, durationMs, closeAtMs) => travel * lib.springSlice(cutMs, startMs, durationMs, true, closeAtMs);
  assert.ok(left(304 - 22, 0, riseMs, narrowCloseAtMs) < 1);
  assert.ok(left(276 - 96, 0, narrowMs, narrowCloseAtMs) < 1);
  assert.ok(left(900 - 276, wideStartMs, wideMs, wideCloseAtMs) < 1);
});

test("the pill close ends within 1 px of rest", () => {
  const widenMs = 420, growMs = 500, clockFadeMs = 140;
  const flightMs = 500, fadeInMs = 200, endMs = widenMs + 660 + 180;
  const totalMs = endMs;
  const growCloseAtMs = totalMs - 60;
  const widenCloseAtMs = growCloseAtMs - Math.round(growMs * 0.76);
  const clockCloseAtMs = widenCloseAtMs - Math.round(widenMs * 0.6);
  const closeLagMs = endMs - (widenMs + flightMs);
  const cutMs = Math.min(lib.closeEnd(widenCloseAtMs, widenMs), lib.closeEnd(clockCloseAtMs, clockFadeMs),
    lib.closeEnd(widenMs + closeLagMs, fadeInMs));
  const left = (travel, startMs, durationMs, closeAtMs) => travel * lib.springSlice(cutMs, startMs, durationMs, true, closeAtMs);
  assert.ok(left(454 - 30, widenMs, growMs, growCloseAtMs) < 1);
  assert.ok(left(800 - 124, 0, widenMs, widenCloseAtMs) < 1);
});

test("columnSpread keeps the open path and levels the row early while closing", () => {
  assert.equal(lib.columnSpread(0.4, false), 0.4);
  assert.equal(lib.columnSpread(1, true), 1);
  assert.equal(lib.columnSpread(0, true), 0);
  // Spine buttons are 48 px apart: with 7 tabs the row spread is 6 * 48 * spread.
  // The spring close is at flight 0.1 for a long time; the row must be level there (under 1 px).
  assert.ok(6 * 48 * lib.columnSpread(0.1, true) < 1);
});

test("an open from rest runs the whole motion; an interrupted open runs only the rest of it", () => {
  assert.equal(lib.slideDurationMs(1000, 0, 1), 1000);
  assert.equal(lib.slideDurationMs(1000, 0.25, 1), 750);
  assert.equal(lib.slideDurationMs(1000, 1, 1), 0);
});

test("a close from fully open stops at the rest time; an interrupted close goes straight back to 0", () => {
  assert.deepEqual({ ...lib.startClose(1, 600, 1000) }, { fromOpen: true, target: 0.6 });
  assert.deepEqual({ ...lib.startClose(0.99, 600, 1000) }, { fromOpen: false, target: 0 });
  assert.deepEqual({ ...lib.startClose(0.3, 600, 1000) }, { fromOpen: false, target: 0 });
  // The close from full open takes only the share of the motion up to the rest time.
  assert.equal(lib.slideDurationMs(1000, 1, lib.startClose(1, 600, 1000).target), 400);
});

test("a step starts to close when the step after it has closed the given share", () => {
  assert.equal(lib.overlapEnd(1000, 500, lib.bigStepHandover), 620);
  assert.equal(lib.overlapEnd(700, 420, lib.smallStepHandover), 448);
});

// A view in miniature: the same calls as Pill.qml, with time stepped by hand.
// One part (spring slice of 400 ms from 0, closing at 1000 of a 1000 ms motion) stands for the motion.
function motion() {
  const totalMs = 1000, restMs = 700, partMs = 400;
  const view = { open: false, closeFromOpen: false, progress: 0, to: 0, speed: 0 };
  const slideTo = (to) => { view.to = to; view.speed = (to - view.progress) / lib.slideDurationMs(totalMs, view.progress, to); };
  return {
    view,
    open() { view.open = true; slideTo(1); },
    close() {
      const c = lib.startClose(view.progress, restMs, totalMs);
      view.closeFromOpen = c.fromOpen;
      view.open = false;
      slideTo(c.target);
    },
    // Moves the straight-line progress for `ms` (it stops at its target).
    run(ms) {
      const next = view.progress + view.speed * ms;
      view.progress = view.speed > 0 ? Math.min(next, view.to) : Math.max(next, view.to);
    },
    part() {
      const closing = !view.open && view.closeFromOpen;
      return lib.springSlice(view.progress * totalMs, 0, partMs, closing, totalMs);
    },
  };
}

test("full open: the part rises along the spring and ends at 1", () => {
  const m = motion();
  m.open();
  m.run(200);
  assert.ok(Math.abs(m.part() - ease.spring(0.5)) < 1e-9);
  m.run(800);
  assert.equal(m.view.progress, 1);
  assert.equal(m.part(), 1);
});

test("full close: the part falls, is at rest at the rest time, and the open path is not replayed", () => {
  const m = motion();
  m.open(); m.run(1000);
  m.close();
  assert.equal(m.view.closeFromOpen, true);
  m.run(100);
  const early = m.part();
  assert.ok(early < 1 && early > 0);
  m.run(10000);
  assert.equal(m.view.progress, 0.7);
  assert.ok(m.part() < 0.003);
});

test("interrupted open: a close then an open again continues from where the progress is", () => {
  const m = motion();
  m.open(); m.run(1000);
  m.close(); m.run(300);
  const before = m.view.progress;
  m.open();
  assert.equal(m.view.to, 1);
  assert.equal(m.view.progress, before);
  assert.equal(m.part(), lib.springSlice(before * 1000, 0, 400, false, 1000));
  m.run(10000);
  assert.equal(m.part(), 1);
});

test("interrupted close: a close started mid-open plays the open back in a straight line to 0", () => {
  const m = motion();
  m.open(); m.run(300);
  const at = m.part();
  m.close();
  assert.equal(m.view.closeFromOpen, false);
  assert.equal(m.view.to, 0);
  assert.equal(m.part(), at);
  m.run(150);
  assert.ok(Math.abs(m.part() - ease.spring(lib.slice(150, 0, 400))) < 1e-9);
  m.run(10000);
  assert.equal(m.part(), 0);
});
