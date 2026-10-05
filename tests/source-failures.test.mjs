// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/SourceFailures.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);
const HOUR = 3600000;

test("a source logs its first failure and then stays silent for one hour", () => {
  const seen = {};
  assert.equal(lib.report(seen, "usage", "bad output", 1000), "berri-shell: usage data failed (bad output)");
  assert.equal(lib.report(seen, "usage", "bad output", 1000 + 5 * 60000), "");
  assert.equal(lib.report(seen, "usage", "no output", 1000 + HOUR - 1), "");
  assert.equal(lib.report(seen, "usage", "no output", 1000 + HOUR), "berri-shell: usage data failed (no output)");
});

test("sources keep separate periods", () => {
  const seen = {};
  lib.report(seen, "code stats", "bad output", 5000);
  assert.equal(lib.report(seen, "code commits", "no output", 6000), "berri-shell: code commits data failed (no output)");
  assert.equal(lib.report(seen, "code stats", "bad output", 7000), "");
});

test("a clock that moves back does not silence a source", () => {
  const seen = {};
  lib.report(seen, "weather", "offline", 9e12);
  assert.equal(lib.report(seen, "weather", "offline", 1000), "berri-shell: weather data failed (offline)");
});

test("the line holds only the source and a fixed reason", () => {
  const secret = "Bearer sk-abc https://x.test/?token=123 {\"email\":\"a@b.c\"}";
  assert.equal(lib.line("usage", secret), "berri-shell: usage data failed (unknown)");
  assert.doesNotMatch(lib.line("usage", secret), /sk-abc|token|https|email/);
});

test("outputReason tells empty output from unreadable output", () => {
  assert.equal(lib.outputReason(""), "no output");
  assert.equal(lib.outputReason("{oops"), "bad output");
});
