// scripts/backup-saved.sh keeps the last stored text of a saved file before it is replaced.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const script = new URL("../scripts/backup-saved.sh", import.meta.url).pathname;
const mode = (p) => (fs.statSync(p).mode & 0o777).toString(8);
// Runs under the common creation mask 022 (others may read).
const run = (file) => spawnSync("sh", ["-c", 'umask 022; exec sh "$@"', "sh", script, file], { encoding: "utf8" });
const folder = () => fs.mkdtempSync(path.join(os.tmpdir(), "berri-backup-"));

test("the backup holds the exact old bytes and is owner-only", () => {
  const dir = folder();
  const file = path.join(dir, "theme.json");
  const old = Buffer.from('{"broken": \n\xff\xfe no end');
  fs.writeFileSync(file, old, { mode: 0o644 });
  fs.chmodSync(file, 0o644);
  assert.equal(run(file).status, 0);
  assert.deepEqual(fs.readFileSync(file + ".bak"), old);
  assert.equal(mode(file + ".bak"), "600");
  assert.deepEqual(fs.readdirSync(dir).sort(), ["theme.json", "theme.json.bak"]);
});

test("a second backup replaces the first and a missing file needs none", () => {
  const dir = folder();
  const file = path.join(dir, "a.json");
  assert.equal(run(file).status, 0);
  assert.equal(fs.existsSync(file + ".bak"), false);
  fs.writeFileSync(file, "one");
  run(file);
  fs.writeFileSync(file, "two");
  run(file);
  assert.equal(fs.readFileSync(file + ".bak", "utf8"), "two");
});

test("a file that cannot be copied gives a failure and leaves the old backup", () => {
  const dir = folder();
  const file = path.join(dir, "a.json");
  fs.writeFileSync(file + ".bak", "older");
  fs.mkdirSync(file);
  assert.notEqual(run(file).status, 0);
  assert.equal(fs.readFileSync(file + ".bak", "utf8"), "older");
  assert.equal(fs.existsSync(file + ".bak.tmp"), false);
  assert.equal(spawnSync("sh", [script], { encoding: "utf8" }).status, 2);
});
