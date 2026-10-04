// Runs the real views with fake system services. It never starts a shell instance.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));

test("volume, playback, and brightness follow their shared owners in QML", () => {
  mkdirSync(path.join(root, "scratchpad"), { recursive: true });
  const run = mkdtempSync(path.join(root, "scratchpad/qml-test-"));
  const imports = path.join(run, "imports");
  cpSync(path.join(root, "tests/qml/imports"), imports, { recursive: true });

  for (const folder of ["common", "tabs/home", "tabs/media", "logic"]) {
    const target = path.join(imports, "qs", folder);
    cpSync(path.join(root, folder), target, { recursive: true });
    if (folder === "logic") continue;
    const types = readdirSync(target).filter(name => name.endsWith(".qml"));
    writeFileSync(path.join(target, "qmldir"),
      `module qs.${folder.replaceAll("/", ".")}\n` +
      types.map(name => `${name.slice(0, -4)} 1.0 ${name}\n`).join(""));
  }
  for (const name of ["MediaPlayer", "Brightness"]) {
    cpSync(path.join(root, `services/${name}.qml`), path.join(imports, `qs/services/${name}.qml`));
  }

  const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
  const result = spawnSync(runner, ["-input", path.join(root, "tests/qml"), "-import", imports], {
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
