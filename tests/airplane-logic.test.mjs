// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/AirplaneLogic.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);
// Objects made inside the vm have another prototype; copy them for deepEqual.
const plain = (value) => JSON.parse(JSON.stringify(value));

test("airplane on: remembers both radios and turns them off", () => {
  const next = plain(lib.nextState({ air: false, wifi: true, bt: false }, "toggleAir"));
  assert.deepEqual(next, { air: true, memoValid: true, memoWifi: true, memoBt: false, wifi: false, bt: false });
});

test("airplane off: restores the remembered radios", () => {
  const next = plain(lib.nextState({ air: true, memoValid: true, memoWifi: false, memoBt: true }, "toggleAir"));
  assert.deepEqual(next, { air: false, memoValid: false, memoWifi: false, memoBt: false, wifi: false, bt: true });
});

test("airplane off with nothing remembered: both radios come on", () => {
  const next = plain(lib.nextState({ air: true, memoValid: false }, "toggleAir"));
  assert.equal(next.wifi, true);
  assert.equal(next.bt, true);
});

test("a radio turned on clears airplane mode and its memory", () => {
  const next = plain(lib.nextState({ air: true, memoValid: true, memoWifi: true, memoBt: true }, "radioOn"));
  assert.deepEqual(next, { air: false, memoValid: false, memoWifi: false, memoBt: false });
});

test("a radio turned on while airplane is off changes nothing", () => {
  assert.deepEqual(plain(lib.nextState({ air: false }, "radioOn")), {});
});

test("unknown action changes nothing", () => {
  assert.deepEqual(plain(lib.nextState({ air: true }, "other")), {});
});
