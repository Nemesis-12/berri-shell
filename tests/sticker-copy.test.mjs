// Run: node --test tests/sticker-copy.test.mjs
// Runs the real sticker-display-copy.sh in a temporary folder.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import path from "node:path";

const script = fileURLToPath(new URL("../scripts/sticker-display-copy.sh", import.meta.url));
const hasMagick = spawnSync("magick", ["-version"]).status === 0;

function seconds(offset) {
  return Date.now() / 1000 + offset;
}

test("a new display copy removes older copies and keeps the source picture", { skip: !hasMagick }, t => {
  const folder = mkdtempSync(path.join(tmpdir(), "berri-sticker-"));
  t.after(() => rmSync(folder, { recursive: true, force: true }));
  const file = name => path.join(folder, name);

  const source = file("sticker.png");
  assert.equal(spawnSync("magick", ["-size", "40x20", "xc:red", source]).status, 0);
  utimesSync(source, seconds(-60), seconds(-60));

  // Copies made from an older picture, and the name used before copies had a size.
  for (const name of ["sticker-display.png", "sticker-display-250x300.png"]) {
    writeFileSync(file(name), "old");
    utimesSync(file(name), seconds(-3600), seconds(-3600));
  }
  // Another monitor's copy of the same picture is newer than the source.
  writeFileSync(file("sticker-display-500x600.png"), "other monitor");
  utimesSync(file("sticker-display-500x600.png"), seconds(-30), seconds(-30));
  writeFileSync(file("notes.png"), "not a sticker file");
  utimesSync(file("notes.png"), seconds(-3600), seconds(-3600));

  const target = file("sticker-display-100x50.png");
  const result = spawnSync("sh", [script, source, target, "100", "50"], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);

  const size = spawnSync("magick", ["identify", "-format", "%wx%h", target], { encoding: "utf8" }).stdout;
  assert.equal(size, "100x50");
  assert.equal(existsSync(file("sticker-display.png")), false);
  assert.equal(existsSync(file("sticker-display-250x300.png")), false);
  assert.equal(existsSync(file("sticker-display-500x600.png")), true);
  assert.equal(existsSync(source), true);
  assert.equal(existsSync(file("notes.png")), true);
});
