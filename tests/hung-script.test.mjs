// Run: node --test tests/hung-script.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));

// Runs the real CachedSource with a fake script process that never exits.
test("a script that never exits is killed and runs again in the next cycle", () => {
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const folder = fs.mkdtempSync(path.join(repo, "scratchpad/hung-script-"));
  try {
    fs.cpSync(path.join(repo, "tests/fixtures/hung-script"), folder, { recursive: true });
    const source = fs.readFileSync(path.join(repo, "services/CachedSource.qml"), "utf8")
      .replace(/^import Quickshell\n/m, "")
      .replace(/^import Quickshell.Io\n/m, "")
      .replace(/Quickshell\.shellPath\(/g, "(")
      .replace(/"\.\.\/logic\/([A-Za-z]+\.js)"/g, (_, name) => JSON.stringify(path.join(repo, "logic", name)));
    fs.writeFileSync(path.join(folder, "CachedSource.qml"), source);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1" };
    delete env.LD_LIBRARY_PATH;
    const result = spawnSync("qml6", [path.join(folder, "test.qml")], { env, encoding: "utf8", timeout: 60000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr + result.stdout, /Hung script checks passed/);
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
});
