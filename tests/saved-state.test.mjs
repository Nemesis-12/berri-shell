// Runs the real SavedState and Wallpapers files in Qt with a fake disk and fake processes.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));

test("saved settings report failed writes, keep a backup and refuse unsafe deletes in QML", () => {
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const copy = fs.mkdtempSync(path.join(repo, "scratchpad/saved-state-"));
  try {
    fs.cpSync(path.join(repo, "tests/fixtures/saved-state-qml"), copy, { recursive: true });
    fs.cpSync(path.join(repo, "tests/qml-saved-state"), path.join(copy, "tests"), { recursive: true });
    fs.cpSync(path.join(repo, "logic"), path.join(copy, "logic"), { recursive: true });
    fs.mkdirSync(path.join(copy, "common"));
    fs.copyFileSync(path.join(repo, "common/SavedState.qml"), path.join(copy, "common/SavedState.qml"));
    fs.writeFileSync(path.join(copy, "common/qmldir"), "module qs.common\nSavedState 1.0 SavedState.qml\n");
    fs.copyFileSync(path.join(repo, "services/Wallpapers.qml"), path.join(copy, "services/Wallpapers.qml"));
    fs.writeFileSync(path.join(copy, "services/qmldir"),
      "module qs.services\nsingleton Theme 1.0 Theme.qml\nsingleton Wallpapers 1.0 Wallpapers.qml\n");
    fs.mkdirSync(path.join(copy, "qs"));
    for (const name of ["common", "services", "logic"]) fs.symlinkSync(path.join(copy, name), path.join(copy, "qs", name));

    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1" };
    delete env.LD_LIBRARY_PATH;
    const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
    const result = spawnSync(runner, ["-import", copy, "-input", path.join(copy, "tests")],
      { cwd: copy, env, encoding: "utf8", timeout: 30000 });
    assert.equal(result.error, undefined, `Cannot run ${runner}: ${result.error?.message}`);
    const output = `${result.stdout}${result.stderr}`;
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /\b(?:QCRITICAL|FAIL!)\s*:/, output);
  } finally {
    fs.rmSync(copy, { recursive: true, force: true });
  }
});
