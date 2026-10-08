// Saved wallpaper and calendar entries cannot point outside their own folders.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { calendarModule } from "./fixtures/calendar-code.mjs";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

function load(name) {
  const code = vm.createContext({});
  vm.runInContext(fs.readFileSync(new URL(`../logic/${name}`, import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), code);
  return code;
}

const walls = load("WallpaperPaths.js");
const dir = "/home/u/.local/share/berri-shell/wallpapers";

test("only a file directly inside the wallpaper folder may be deleted", () => {
  assert.equal(walls.isLibraryFile(dir, dir + "/a.png"), true);
  assert.equal(walls.isLibraryFile(dir, dir + "/a b-1.jpg"), true);
  for (const bad of ["/home/u/outside.png", dir, dir + "/", dir + "/..", dir + "/.", dir + "/../x.png",
    dir + "/sub/a.png", dir + "-evil/a.png", "", dir + "/a.png/", 42, null])
    assert.equal(walls.isLibraryFile(dir, bad), false, String(bad));
  assert.equal(walls.isLibraryFile(dir + "/", dir + "/a.png"), true);
  assert.equal(walls.isLibraryFile("", "/a.png"), false);
});

const saved = calendarModule("SavedCalendars.js");

test("saved calendar entries keep only names that stay inside the calendar folder", () => {
  const ok = (e) => saved.isSafeEntry(e);
  assert.equal(ok({ id: "f-1ab", kind: "file", file: "work.ics" }), true);
  assert.equal(ok({ id: "l-9z", kind: "link", file: "subscriptions/l-9z.ics" }), true);
  assert.equal(ok({ id: "f-1ab", kind: "file", file: "/etc/x.ics" }), false);
  assert.equal(ok({ id: "f-1ab", kind: "file", file: "sub/x.ics" }), false);
  assert.equal(ok({ id: "f-1ab", kind: "file", file: "..ics" }), false);
  assert.equal(ok({ id: "f-1ab", kind: "file", file: "x.txt" }), false);
  assert.equal(ok({ id: "f-1ab", kind: "file", file: "berri.ics" }), false);
  assert.equal(ok({ id: "l-9z", kind: "link", file: "subscriptions/other.ics" }), false);
  assert.equal(ok({ id: "l-9z", kind: "link", file: "work.ics" }), false);
  for (const id of ["../x", "a/b", "a.b", "", "l-9z\n", "x".repeat(65)])
    assert.equal(ok({ id, kind: "link", file: `subscriptions/${id}.ics` }), false, id);
  assert.equal(ok({ id: "f-1ab", kind: "other", file: "a.ics" }), false);
});

test("saved calendar entries and links are checked in the offscreen calendar service", () => {
  const result = calendarOffscreen(() => {}, "qml/tst_calendar_saved_entries.qml");
  assert.equal(result.ok, true, result.error?.message || result.output);
});
