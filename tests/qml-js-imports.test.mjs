import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const skip = new Set([".git", "scratchpad", "node_modules", "tests", "target"]);

function qmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    if (skip.has(entry.name)) return [];
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return qmlFiles(full);
    return entry.name.endsWith(".qml") ? [full] : [];
  });
}

const importPattern = /^import\s+"[^"]+\.js"\s+as\s+(\w+)/gm;

// A QML file that calls a JavaScript library by its alias must import it.
// A part split out of a larger file loses the import unless it is copied too.
test("each QML file imports the JavaScript libraries it uses", () => {
  const files = qmlFiles(root).map(file => ({ file, source: readFileSync(file, "utf8") }));
  const aliases = new Set(files.flatMap(({ source }) => [...source.matchAll(importPattern)].map(m => m[1])));
  const missing = [];
  for (const { file, source } of files) {
    const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    const imported = new Set([...source.matchAll(importPattern)].map(m => m[1]));
    for (const alias of aliases) {
      if (!imported.has(alias) && new RegExp(`(?<![\\w./])${alias}\\.\\w`).test(code))
        missing.push(`${path.relative(root, file)} uses ${alias} without importing it`);
    }
  }
  assert.deepEqual(missing, []);
});
