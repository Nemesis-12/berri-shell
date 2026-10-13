// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/MediaRules.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

// The enum value of "playing" is passed in; the test uses an arbitrary number.
const PLAYING = 1;
const player = (extra = {}) => ({ playbackState: 2, lengthSupported: true, length: 180, canSeek: true, positionSupported: true, ...extra });

test("a usable length is returned in seconds", () => {
  assert.equal(lib.knownLength(player()), 180);
});

test("unknown, zero, huge or invalid length gives 0", () => {
  assert.equal(lib.knownLength(player({ lengthSupported: false })), 0);
  assert.equal(lib.knownLength(player({ length: 0 })), 0);
  assert.equal(lib.knownLength(player({ length: -5 })), 0);
  assert.equal(lib.knownLength(player({ length: Infinity })), 0);
  assert.equal(lib.knownLength(player({ length: NaN })), 0);
  assert.equal(lib.knownLength(player({ length: 92233720368054 })), 0);
  assert.equal(lib.knownLength(null), 0);
});

test("seek needs a known length, seek support and position support", () => {
  assert.equal(lib.canSeek(player()), true);
  assert.equal(lib.canSeek(player({ length: 0 })), false);
  assert.equal(lib.canSeek(player({ canSeek: false })), false);
  assert.equal(lib.canSeek(player({ positionSupported: false })), false);
  assert.equal(lib.canSeek(null), false);
});

test("the shown position is empty for unsupported or invalid positions", () => {
  assert.equal(lib.knownPosition(player(), 61), 61);
  assert.equal(lib.knownPosition(player({ positionSupported: false }), 61), -1);
  assert.equal(lib.knownPosition(player(), 92233720368054), -1);
  assert.equal(lib.knownPosition(player(), NaN), -1);
});

test("time text shows both times, only the elapsed time, or nothing", () => {
  assert.equal(lib.timeText(60, 180), "1:00 / 3:00");
  assert.equal(lib.timeText(60, 0), "1:00");
  assert.equal(lib.timeText(-1, 0), "");
  assert.equal(lib.timeText(-1, 180), "");
});

test("progress is 0 with an unknown position or length, and stays between 0 and 1", () => {
  assert.equal(lib.progress(60, 180), 1 / 3);
  assert.equal(lib.progress(-1, 180), 0);
  assert.equal(lib.progress(60, 0), 0);
  assert.equal(lib.progress(200, 180), 1);
});

test("a length of exactly 100 hours counts, a little more does not", () => {
  const limit = 100 * 3600;
  assert.equal(lib.knownLength(player({ length: limit })), limit);
  assert.equal(lib.knownLength(player({ length: limit + 1 })), 0);
  assert.equal(lib.knownPosition(player(), limit), limit);
  assert.equal(lib.knownPosition(player(), limit + 1), -1);
});

test("shuffle and repeat need support and control permission", () => {
  assert.equal(lib.canShuffle({ shuffleSupported: true, canControl: true }), true);
  assert.equal(lib.canShuffle({ shuffleSupported: true, canControl: false }), false);
  assert.equal(lib.canShuffle({ shuffleSupported: false, canControl: true }), false);
  assert.equal(lib.canRepeat({ loopSupported: true, canControl: true }), true);
  assert.equal(lib.canRepeat({ loopSupported: true, canControl: false }), false);
  assert.equal(lib.canRepeat(null), false);
});

test("a paused player is remembered by the player, not by the track id", () => {
  const a = { uniqueId: 0, playbackState: 2 };
  const b = { uniqueId: 0, playbackState: 1 };
  const first = lib.choosePlayer([a, b], null, PLAYING);
  assert.equal(first.player, b);
  b.playbackState = 2;
  const second = lib.choosePlayer([a, b], first.remembered, PLAYING);
  assert.equal(second.player, b);
});

test("a removed remembered player is forgotten", () => {
  const a = { playbackState: 2 };
  const b = { playbackState: 2 };
  assert.equal(lib.choosePlayer([a], b, PLAYING).player, a);
  assert.equal(lib.choosePlayer([], b, PLAYING).player, null);
});

test("a playing player wins and the first player is the last choice", () => {
  const a = { playbackState: 2 };
  const b = { playbackState: 2 };
  assert.equal(lib.choosePlayer([a, b], null, PLAYING).player, a);
});
