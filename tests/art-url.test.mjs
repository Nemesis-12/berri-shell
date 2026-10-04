// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/ArtUrl.js", import.meta.url), "utf8").replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

test("artwork accepts local file and HTTPS links", () => {
  assert.equal(lib.safeArtUrl("file:///tmp/a.png"), "file:///tmp/a.png");
  assert.equal(lib.safeArtUrl("https://example.com/a.png"), "https://example.com/a.png");
  assert.equal(lib.safeArtUrl("HTTPS://example.com/a.png"), "HTTPS://example.com/a.png");
});

test("artwork rejects every other link", () => {
  for (const url of ["http://127.0.0.1:8000/a.png", "ftp://x/a.png", "data:image/png;base64,AA", "qrc:/a.png",
    "image://theme/x", "/tmp/a.png", " http://x", "", null, undefined]) {
    assert.equal(lib.safeArtUrl(url), "", String(url));
  }
});
