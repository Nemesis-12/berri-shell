// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = fileURLToPath(new URL("../", import.meta.url));
const motionFiles = ["common/StandardMotion.qml", "common/SpringMotion.qml", "common/EmphasizedMotion.qml", "common/StandardColorMotion.qml"];

function sources(extension) {
  const found = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!["tests", "scratchpad", ".git", "node_modules", "assets"].includes(entry.name)) walk(full);
      } else if (entry.name.endsWith(extension)) {
        found.push([path.relative(repo, full), fs.readFileSync(full, "utf8")]);
      }
    }
  };
  walk(repo);
  return found;
}

test("custom animation curves exist only in the shared motion components", () => {
  const bad = sources(".qml")
    .filter(([file, text]) => !motionFiles.includes(file) && file !== "services/Theme.qml")
    .filter(([, text]) => /bezierCurve|Easing\.BezierSpline/.test(text))
    .map(([file]) => file);
  assert.deepEqual(bad, []);
  for (const file of motionFiles) assert.ok(fs.existsSync(path.join(repo, file)), file);
});

test("no animation uses a raw 180 ms duration", () => {
  const bad = [];
  for (const [file, text] of sources(".qml")) {
    if (file === "services/Theme.qml") continue;
    text.split("\n").forEach((line, i) => {
      if (/\bduration:\s*180\b/.test(line) || /\bfadeOutMs:\s*180\b/.test(line)) bad.push(`${file}:${i + 1}`);
    });
  }
  assert.deepEqual(bad, []);
});

test("seconds-to-text exists only in the shared time formatter", () => {
  const names = /function\s+(formatDuration|uptime|duration|timeLeft)\s*\(/;
  const bad = sources(".js").concat(sources(".qml"))
    .filter(([file, text]) => file !== "logic/Times.js" && names.test(text))
    .map(([file]) => file);
  // CodeFormat.timeLeft only turns two dates into seconds for Times.duration.
  assert.deepEqual(bad.filter(file => file !== "logic/CodeFormat.js"), []);
  const code = fs.readFileSync(path.join(repo, "logic/CodeFormat.js"), "utf8");
  assert.match(code, /Times\.duration\(/);
});

test("day shift and display scale have one definition", () => {
  for (const [file, text] of sources(".js")) {
    if (file === "logic/Times.js") continue;
    assert.doesNotMatch(text, /setDate\(/, `${file} shifts dates itself`);
  }
  const guards = sources(".qml").filter(([, text]) => /devicePixelRatio\s*>\s*0\s*\?/.test(text)).map(([file]) => file);
  assert.deepEqual(guards, []);
});
