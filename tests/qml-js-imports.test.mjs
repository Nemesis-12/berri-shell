import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const importPattern = /^import\s+"[^"]+\.js"\s+as\s+(\w+)/gm;

// Tracked source files only: other tests write temporary QML copies while this one runs.
function sourceFiles() {
  return execFileSync("git", ["ls-files", "*.qml"], { cwd: root, encoding: "utf8" })
    .split("\n")
    .filter(file => file && !file.startsWith("tests/"));
}

// A QML file that calls a JavaScript library by its alias must import it.
// A part split out of a larger file loses the import unless it is copied too.
test("each QML file imports the JavaScript libraries it uses", () => {
  const files = sourceFiles().map(file => {
    const source = readFileSync(path.join(root, file), "utf8");
    const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
    const imported = new Set([...source.matchAll(importPattern)].map(m => m[1]));
    return { file, code, imported };
  });
  const aliases = new Set(files.flatMap(({ imported }) => [...imported]));
  const missing = [];
  for (const { file, code, imported } of files) {
    for (const alias of aliases) {
      if (!imported.has(alias) && new RegExp(`(?<![\\w./])${alias}\\.\\w`).test(code))
        missing.push(`${file} uses ${alias} without importing it`);
    }
  }
  assert.deepEqual(missing, []);
});
