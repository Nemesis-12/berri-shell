// IconLookup.js is a QML library (".pragma library"), so it is evaluated in a vm context.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs
  .readFileSync(new URL("../logic/IconLookup.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");

// A fresh context per test gives each test its own "already warned" list.
function load() {
  const warnings = [];
  const lib = vm.createContext({ console: { warn: (text) => warnings.push(text) } });
  vm.runInContext(source, lib);
  return { lib, warnings };
}

const paths = { check: "M1 1L2 2" };

test("known names give their path and no warning", () => {
  const { lib, warnings } = load();
  assert.equal(lib.pathFor(paths, "check"), "M1 1L2 2");
  assert.deepEqual(warnings, []);
});

test("an empty name means no icon and no warning", () => {
  const { lib, warnings } = load();
  assert.equal(lib.pathFor(paths, ""), "");
  assert.deepEqual(warnings, []);
});

test("an unknown name warns exactly once, however often it is read", () => {
  const { lib, warnings } = load();
  for (let i = 0; i < 3; i++) assert.equal(lib.pathFor(paths, "nope"), "");
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /nope/);
});

test("names from Object.prototype count as unknown", () => {
  const { lib, warnings } = load();
  assert.equal(lib.pathFor(paths, "toString"), "");
  assert.equal(warnings.length, 1);
});

test("every Icon.qml lookup goes through pathFor", () => {
  const icon = fs.readFileSync(new URL("../common/Icon.qml", import.meta.url), "utf8");
  assert.match(icon, /IconLookup\.pathFor\(Icons\.paths, root\.name\)/);
});
