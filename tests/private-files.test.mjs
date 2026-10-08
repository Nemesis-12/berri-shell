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
    [path.join(root, "bin", "parser"), path.join(sub, "l-x"), sub, "127", "70", "71"], { ...env, BERRI_FEED_URL: "https://example.test/f.ics" });
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
  for (const file of ["services/SavedState.qml", "services/CalendarFiles.qml"]) {
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

// A fake parser that writes its output with the creation mask it inherits.
function fakeParser(root) {
  const parser = path.join(root, "parser");
  fs.writeFileSync(parser, `#!/bin/sh\nprintf '{}' > "$2"\n`, { mode: 0o755 });
  return parser;
}

test("rebuilding subscription records writes a json file with mode 600", () => {
  const root = tmp();
  const sub = path.join(root, "subscriptions");
  fs.mkdirSync(sub);
  fs.writeFileSync(path.join(sub, "l-x.ics"), "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n");
  const result = runOpen("refresh-records.sh", [fakeParser(root), path.join(sub, "l-x.ics"), path.join(sub, "l-x.json"), "127"]);
  assert.equal(result.status, 0);
  assert.equal(mode(path.join(sub, "l-x.json")), "600");
});

test("rebuilding records reports a missing parser and skips a missing .ics file", () => {
  const root = tmp();
  fs.writeFileSync(path.join(root, "a.ics"), "x");
  assert.equal(runOpen("refresh-records.sh", [path.join(root, "none"), path.join(root, "a.ics"), path.join(root, "a.json"), "127"]).status, 127);
  assert.equal(runOpen("refresh-records.sh", [fakeParser(root), path.join(root, "none.ics"), path.join(root, "none.json"), "127"]).status, 0);
});

test("CalendarFiles.qml starts the record rebuild through refresh-records.sh", () => {
  const source = fs.readFileSync(path.join(repo, "services/CalendarFiles.qml"), "utf8");
  assert.match(source, /scripts\/refresh-records\.sh/);
});

test("adding a wallpaper makes a private library folder and a 600 copy", () => {
  const root = tmp();
  const picture = path.join(root, "pic.png");
  fs.writeFileSync(picture, "PNG");
  fs.chmodSync(picture, 0o644);
  const library = path.join(root, "share", "berri-shell", "wallpapers");
  const first = runOpen("add-wallpaper.sh", [picture, library]);
  assert.equal(first.status, 0);
  const second = runOpen("add-wallpaper.sh", [picture, library]);
  assert.equal(second.stdout, path.join(library, "pic-1.png"));
  assert.equal(mode(library), "700");
  assert.equal(mode(path.join(root, "share", "berri-shell")), "700");
  assert.equal(mode(first.stdout), "600");
  assert.equal(mode(second.stdout), "600");
  assert.equal(mode(picture), "644");
});

test("adding a wallpaper fixes an old library folder", () => {
  const root = tmp();
  const picture = path.join(root, "pic.png");
  fs.writeFileSync(picture, "PNG");
  const library = path.join(root, "wallpapers");
  fs.mkdirSync(library);
  fs.writeFileSync(path.join(library, "old.png"), "OLD");
  fs.chmodSync(library, 0o755);
  fs.chmodSync(path.join(library, "old.png"), 0o644);
  assert.equal(runOpen("add-wallpaper.sh", [picture, library]).status, 0);
  assert.equal(mode(library), "700");
  assert.equal(mode(path.join(library, "old.png")), "600");
});

test("recent answers of the data scripts are owner-only", () => {
  const cache = path.join(tmp(), "berri-shell");
  fs.mkdirSync(cache, { mode: 0o755 });
  fs.chmodSync(cache, 0o755);
  const code = `from pathlib import Path; from recent_answers import save_answer; import sys; save_answer(Path(sys.argv[1]) / "x.json", "{}")`;
  const run = () => spawnSync("sh", ["-c", 'umask 022; exec python3 -c "$0" "$@"', code, cache], { cwd: scripts, encoding: "utf8" });
  assert.equal(run().status, 0);
  assert.equal(mode(cache), "700");
  assert.equal(mode(path.join(cache, "x.json")), "600");
  fs.chmodSync(path.join(cache, "x.json"), 0o644);
  assert.equal(run().status, 0);
  assert.equal(mode(path.join(cache, "x.json")), "600");
});

test("the feed parser writes a 600 json file under mask 022", () => {
  const parser = path.join(repo, "tools/feed-to-records/target/debug/feed-to-records");
  const cargo = spawnSync("cargo", ["build", "--offline", "--quiet", "--manifest-path", path.join(repo, "tools/feed-to-records/Cargo.toml")], { encoding: "utf8" });
  assert.equal(cargo.status, 0, cargo.stderr);
  const root = tmp();
  fs.writeFileSync(path.join(root, "f.ics"), "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n");
  const result = spawnSync("sh", ["-c", 'umask 022; exec "$@"', "sh", parser, path.join(root, "f.ics"), path.join(root, "f.json")], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(mode(path.join(root, "f.json")), "600");
});
