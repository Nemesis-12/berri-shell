// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const lib = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/ThemeColors.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), lib);

const themes = JSON.parse(fs.readFileSync(new URL("../data/themes.json", import.meta.url), "utf8"));
const hex = (c) => "#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");

test("an empty palette still gives all nine required colors", () => {
  const raw = lib.rawPalette({});
  assert.equal(lib.rawKeys.length, 9);
  for (const key of lib.rawKeys) {
    for (const part of ["r", "g", "b", "a"]) assert.equal(typeof raw[key][part], "number", `${key}.${part}`);
  }
  assert.equal(hex(raw.accent), "#c28bf2");
  assert.deepEqual(Object.keys(lib.rawPalette(undefined)).sort(), [...lib.rawKeys].sort());
});

test("tokens of an empty palette equal tokens of the fallback palette", () => {
  const names = lib.tokenTable.map(t => t.name);
  const tokens = lib.computeTokens(lib.rawPalette({}));
  assert.deepEqual(Object.keys(tokens).sort(), [...names].sort());
  assert.deepEqual(lib.computeTokens({}), tokens);
});

test("one table entry adds one token", () => {
  const table = lib.tokenTable.concat([{ name: "testToken", make: raw => lib.oklabMix(raw.accent, raw.shell || raw.dark_background, 50) }]);
  const raw = lib.rawPalette(themes[0].c);
  const tokens = lib.computeTokens(raw, table);
  assert.equal(Object.keys(tokens).length, lib.tokenTable.length + 1);
  assert.equal(typeof tokens.testToken.r, "number");
  assert.equal("testToken" in lib.computeTokens(raw), false);
});

test("tokens keep their former values for the first theme", () => {
  // Values taken from the shell before the refactor (Theme.qml computeTokens, OKLab mixes).
  const tokens = lib.computeTokens(lib.rawPalette(themes[0].c));
  assert.equal(hex(tokens.shell), "#251c40");
  assert.equal(hex(tokens.accent), "#c28bf2");
  assert.equal(hex(tokens.raised), "#3b2c62");
  assert.equal(hex(lib.oklabMix(tokens.raised, tokens.fg, 92)), "#483a6e");
  assert.equal(tokens.accentFill.a, 0.18);
  assert.equal(tokens.accentLine.a, 0.45);
});

test("the oklab mix of a color with itself is that color", () => {
  const c = lib.hexToRgb("#3b2c62");
  assert.equal(hex(lib.oklabMix(c, c, 37)), "#3b2c62");
  assert.equal(hex(lib.oklabMix(lib.hexToRgb("#000000"), lib.hexToRgb("#ffffff"), 100)), "#000000");
  assert.equal(hex(lib.oklabMix(lib.hexToRgb("#000000"), lib.hexToRgb("#ffffff"), 0)), "#ffffff");
});

test("switch options choose the wallpaper transition, never the duration", () => {
  for (const durationMs of [449, 450, 451]) {
    const plan = lib.switchPlan({ durationMs, wallpaper: true });
    assert.equal(plan.wallpaper, true, String(durationMs));
    assert.equal(plan.durationMs, durationMs);
    assert.equal(lib.switchPlan({ durationMs }).wallpaper, false, String(durationMs));
  }
  assert.deepEqual({ ...lib.switchPlan() }, { animate: true, persist: true, durationMs: 450, wallpaper: false });
  assert.equal(lib.switchPlan({ animate: false, wallpaper: true }).wallpaper, false);
  assert.equal(lib.switchPlan({ persist: false }).persist, false);
});

test("Theme.qml declares one color property for each table entry", () => {
  const theme = fs.readFileSync(new URL("../services/Theme.qml", import.meta.url), "utf8");
  for (const { name } of lib.tokenTable) assert.match(theme, new RegExp(`property color ${name}:`), name);
});
