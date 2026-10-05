// Stored state and calendar files are owner-only, even with a default creation mask of 022.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const scripts = new URL("../scripts/", import.meta.url).pathname;
const repo = new URL("../", import.meta.url).pathname;
const mode = (p) => (fs.statSync(p).mode & 0o777).toString(8);
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "berri-private-"));

// Runs a script under the common creation mask 022 (others may read).
function runOpen(script, args, env = {}) {
  return spawnSync("sh", ["-c", 'umask 022; exec sh "$@"', "sh", path.join(scripts, script), ...args],
    { env: { ...process.env, ...env }, encoding: "utf8" });
}

test("private-folder.sh makes a missing folder mode 700 and keeps its parents out of reach", () => {
  const root = tmp();
  const dir = path.join(root, "a", "b");
  assert.equal(runOpen("private-folder.sh", [dir]).status, 0);
  assert.equal(mode(dir), "700");
  assert.equal(mode(path.join(root, "a")), "700");
});

test("private-folder.sh fixes an old folder and its files", () => {
  const dir = path.join(tmp(), "state");
  fs.mkdirSync(dir, { mode: 0o755 });
  fs.chmodSync(dir, 0o755);
  fs.writeFileSync(path.join(dir, "theme.json"), "{}", { mode: 0o644 });
  fs.chmodSync(path.join(dir, "theme.json"), 0o644);
  fs.mkdirSync(path.join(dir, "sub"));
  fs.chmodSync(path.join(dir, "sub"), 0o755);
  fs.writeFileSync(path.join(dir, "sub", "f.ics"), "x");
  fs.chmodSync(path.join(dir, "sub", "f.ics"), 0o644);
  assert.equal(runOpen("private-folder.sh", [dir]).status, 0);
  assert.equal(mode(dir), "700");
  assert.equal(mode(path.join(dir, "theme.json")), "600");
  assert.equal(mode(path.join(dir, "sub")), "700");
  assert.equal(mode(path.join(dir, "sub", "f.ics")), "600");
});

// A temp folder with a fake parser and a fake curl that copies a local feed.
function feedSetup() {
  const root = tmp();
  const bin = path.join(root, "bin");
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(root, "feed.ics"), "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n");
  fs.writeFileSync(path.join(bin, "parser"), `#!/bin/sh\nprintf '{}' > "$2"\n`, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, "curl"), `#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in -o) o=$2; shift 2;; *) shift;; esac; done\ncp "${root}/feed.ics" "$o"\n`, { mode: 0o755 });
  return { root, sub: path.join(root, "calendar", "subscriptions"), env: { PATH: `${bin}:${process.env.PATH}` } };
}

function download({ root, sub, env }) {
  return runOpen("feed-download.sh",
    ["https://example.test/f.ics", path.join(root, "bin", "parser"), path.join(sub, "l-x"), sub, "127", "70", "71"], env);
}

test("a first feed download makes folder 700 and files 600", () => {
  const s = feedSetup();
  assert.equal(download(s).status, 0);
  assert.equal(mode(s.sub), "700");
  assert.equal(mode(path.join(s.sub, "l-x.ics")), "600");
  assert.equal(mode(path.join(s.sub, "l-x.json")), "600");
});

test("a feed replacement keeps folder 700 and files 600", () => {
  const s = feedSetup();
  assert.equal(download(s).status, 0);
  assert.equal(download(s).status, 0);
  assert.equal(mode(s.sub), "700");
  assert.equal(mode(path.join(s.sub, "l-x.ics")), "600");
  assert.equal(mode(path.join(s.sub, "l-x.json")), "600");
});

test("a replacement fixes an old feed that others could read", () => {
  const s = feedSetup();
  fs.mkdirSync(s.sub, { recursive: true });
  fs.chmodSync(s.sub, 0o755);
  for (const ext of ["ics", "json"]) {
    fs.writeFileSync(path.join(s.sub, `l-x.${ext}`), "OLD");
    fs.chmodSync(path.join(s.sub, `l-x.${ext}`), 0o644);
  }
  assert.equal(download(s).status, 0);
  assert.equal(mode(s.sub), "700");
  assert.equal(mode(path.join(s.sub, "l-x.ics")), "600");
  assert.equal(mode(path.join(s.sub, "l-x.json")), "600");
});

test("state and calendar folders are created through private-folder.sh", () => {
  for (const file of ["common/SavedState.qml", "services/CalendarFiles.qml"]) {
    const source = fs.readFileSync(path.join(repo, file), "utf8");
    assert.match(source, /private-folder\.sh/, file);
    assert.doesNotMatch(source, /"mkdir", "-p"/, file);
  }
});

test("private-folder.sh fixes an existing parent folder before it makes a child", () => {
  const root = path.join(tmp(), "calendar");
  fs.mkdirSync(root);
  fs.chmodSync(root, 0o755);
  assert.equal(runOpen("private-folder.sh", [root, path.join(root, "subscriptions")]).status, 0);
  assert.equal(mode(root), "700");
  assert.equal(mode(path.join(root, "subscriptions")), "700");
});
