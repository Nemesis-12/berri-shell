import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const script = new URL("../scripts/feed-download.sh", import.meta.url).pathname;
const feed = "BEGIN:VCALENDAR\r\nX-WR-CALNAME:New\r\nEND:VCALENDAR\r\n";

// A temp folder with a fake parser, a fake curl (copies a local feed) and a mv that fails when it moves the new records file.
function setup(failNewRecordsMove) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "berri-feed-"));
  const bin = path.join(root, "bin");
  fs.mkdirSync(bin);
  fs.mkdirSync(path.join(root, "sub"));
  fs.writeFileSync(path.join(root, "feed.ics"), feed);
  fs.writeFileSync(path.join(bin, "parser"), `#!/bin/sh\nprintf '{"name":"New","records":[]}' > "$2"\n`, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, "curl"), `#!/bin/sh\nwhile [ $# -gt 0 ]; do case $1 in -o) o=$2; shift 2;; -*) shift;; *) shift;; esac; done\ncp "${root}/feed.ics" "$o"\n`, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, "mv"), `#!/bin/sh\ncase "$1" in */feed.json) ${failNewRecordsMove ? "exit 1" : ":"};; esac\nexec /usr/bin/mv "$@"\n`, { mode: 0o755 });
  return root;
}

function run(root) {
  return spawnSync("sh", [script, "https://example.test/f.ics", path.join(root, "bin", "parser"), path.join(root, "sub", "l-x"), path.join(root, "sub"), "127", "70", "71"],
    { env: { ...process.env, PATH: `${root}/bin:${process.env.PATH}` }, encoding: "utf8" });
}

const read = (root, name) => fs.readFileSync(path.join(root, "sub", name), "utf8");

test("a refresh replaces the feed file and its records together", () => {
  const root = setup();
  fs.writeFileSync(path.join(root, "sub", "l-x.ics"), "OLDICS");
  fs.writeFileSync(path.join(root, "sub", "l-x.json"), "OLDJSON");
  const result = run(root);
  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), path.join(root, "sub", "l-x.json"));
  assert.equal(read(root, "l-x.ics"), feed);
  assert.match(read(root, "l-x.json"), /"name":"New"/);
  assert.deepEqual(fs.readdirSync(path.join(root, "sub")).sort(), ["l-x.ics", "l-x.json"]);
});

test("if the records file cannot be replaced, both old files stay", () => {
  const root = setup(true);
  fs.writeFileSync(path.join(root, "sub", "l-x.ics"), "OLDICS");
  fs.writeFileSync(path.join(root, "sub", "l-x.json"), "OLDJSON");
  const result = run(root);
  assert.equal(result.status, 71);
  assert.equal(read(root, "l-x.ics"), "OLDICS");
  assert.equal(read(root, "l-x.json"), "OLDJSON");
  assert.deepEqual(fs.readdirSync(path.join(root, "sub")).sort(), ["l-x.ics", "l-x.json"]);
});

test("a first download that fails leaves no files", () => {
  const root = setup(true);
  assert.equal(run(root).status, 71);
  assert.deepEqual(fs.readdirSync(path.join(root, "sub")), []);
});
