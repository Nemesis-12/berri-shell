// Run: node --test tests/weather-stale-view.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));

// Runs the real weather views in Qt with a stand-in service. Returns the process result.
function runViews(change = () => {}) {
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const folder = fs.mkdtempSync(path.join(repo, "scratchpad/weather-stale-"));
  try {
    for (const dir of ["logic", "common", "tabs/weather"])
      fs.cpSync(path.join(repo, dir), path.join(folder, dir), { recursive: true });
    fs.mkdirSync(path.join(folder, "services"));
    const stand = path.join(repo, "tests/fixtures/weather-stale");
    for (const name of ["Theme", "Weather", "Clock"])
      fs.copyFileSync(path.join(stand, `${name}.qml`), path.join(folder, `services/${name}.qml`));
    fs.copyFileSync(path.join(stand, "test.qml"), path.join(folder, "test.qml"));
    fs.mkdirSync(path.join(folder, "qs"));
    fs.symlinkSync(path.join(folder, "logic"), path.join(folder, "qs/logic"));
    for (const dir of ["common", "services", "tabs/weather"]) {
      const lines = [`module qs.${dir.replaceAll("/", ".")}`];
      for (const name of fs.readdirSync(path.join(folder, dir)).filter(n => n.endsWith(".qml"))) {
        const singleton = /^pragma Singleton/m.test(fs.readFileSync(path.join(folder, dir, name), "utf8"));
        lines.push(`${singleton ? "singleton " : ""}${name.slice(0, -4)} 1.0 ${name}`);
      }
      fs.writeFileSync(path.join(folder, dir, "qmldir"), lines.join("\n") + "\n");
      const link = path.join(folder, "qs", dir);
      fs.mkdirSync(path.dirname(link), { recursive: true });
      fs.symlinkSync(path.join(folder, dir), link);
    }
    change(folder);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1", QT_FORCE_STDERR_LOGGING: "1" };
    delete env.LD_LIBRARY_PATH;
    const result = spawnSync("qml6", ["-I", folder, path.join(folder, "test.qml")], { env, encoding: "utf8", timeout: 30000 });
    assert.ifError(result.error);
    return result;
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
}

test("a failed refresh dims the readout and shows the data age on Home and in the Weather tab", () => {
  const result = runViews();
  const out = result.stdout + result.stderr;
  assert.equal(result.status, 0, out);
  assert.match(out, /Weather stale checks passed/);
  assert.doesNotMatch(out, /Warning|Error|ReferenceError|TypeError/i);
});
