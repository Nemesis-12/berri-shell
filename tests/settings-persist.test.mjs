// Runs the real Home picture, night-light, and power-mode code with fake system parts.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));

test("saved settings and picture choice survive refreshes and running processes in QML", () => {
  mkdirSync(path.join(root, "scratchpad"), { recursive: true });
  const run = mkdtempSync(path.join(root, "scratchpad/qml-test-"));
  const imports = path.join(run, "imports");
  cpSync(path.join(root, "tests/qml-settings/imports"), imports, { recursive: true });

  const copy = (from, to) => cpSync(path.join(root, from), path.join(imports, to), { recursive: true });
  copy("common/WhileVisible.qml", "qs/common/WhileVisible.qml");
  copy("logic", "qs/logic");
  for (const name of ["Nightlight", "PowerModes"]) copy(`services/${name}.qml`, `qs/services/${name}.qml`);
  mkdirSync(path.join(imports, "qs/tabs/home"), { recursive: true });
  copy("tabs/home/Profile.qml", "qs/tabs/home/Profile.qml");
  writeFileSync(path.join(imports, "qs/tabs/home/qmldir"), "module qs.tabs.home\nProfile 1.0 Profile.qml\n");

  const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
  const result = spawnSync(runner, ["-input", path.join(root, "tests/qml-settings"), "-import", imports], {
    encoding: "utf8",
    timeout: 30000,
    env: {
      ...process.env,
      QT_QPA_PLATFORM: "offscreen",
      QT_QUICK_BACKEND: "software",
      QT_FORCE_STDERR_LOGGING: "1",
      QML_DISABLE_DISK_CACHE: "1",
    },
  });
  assert.equal(result.error, undefined, `Cannot run ${runner}: ${result.error?.message}`);
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test("the shell holds the power mode service from the start", () => {
  const shell = readFileSync(path.join(root, "shell.qml"), "utf8");
  assert.match(shell, /readonly property var \w+: PowerModes\b/);
});
