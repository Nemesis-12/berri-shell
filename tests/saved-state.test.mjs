// Runs the real SavedState and Wallpapers files in Qt with a fake disk and fake processes.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));

function runSavedFiles(input = "tests") {
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const copy = fs.mkdtempSync(path.join(repo, "scratchpad/saved-state-"));
  try {
    fs.cpSync(path.join(repo, "tests/fixtures/saved-state-qml"), copy, { recursive: true });
    fs.cpSync(path.join(repo, "tests/qml-saved-state"), path.join(copy, "tests"), { recursive: true });
    fs.cpSync(path.join(repo, "tests/qml-folder-startup"), path.join(copy, "startup"), { recursive: true });
    fs.copyFileSync(path.join(repo, "services/FolderRoots.qml"), path.join(copy, "services/FolderRoots.qml"));
    fs.copyFileSync(path.join(repo, "services/CalendarFiles.qml"), path.join(copy, "services/CalendarFiles.qml"));
    fs.cpSync(path.join(repo, "logic"), path.join(copy, "logic"), { recursive: true });
    fs.copyFileSync(path.join(repo, "services/SavedState.qml"), path.join(copy, "services/SavedState.qml"));
    fs.copyFileSync(path.join(repo, "services/Wallpapers.qml"), path.join(copy, "services/Wallpapers.qml"));
    fs.writeFileSync(path.join(copy, "services/qmldir"),
      "module qs.services\nsingleton Theme 1.0 Theme.qml\nsingleton Wallpapers 1.0 Wallpapers.qml\nSavedState 1.0 SavedState.qml\nCalendarFiles 1.0 CalendarFiles.qml\nsingleton FolderRoots 1.0 FolderRoots.qml\n");
    fs.mkdirSync(path.join(copy, "qs"));
    for (const name of ["services", "logic"]) fs.symlinkSync(path.join(copy, name), path.join(copy, "qs", name));

    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1" };
    delete env.LD_LIBRARY_PATH;
    const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
    const result = spawnSync(runner, ["-import", copy, "-input", path.join(copy, input)],
      { cwd: copy, env, encoding: "utf8", timeout: 30000 });
    assert.equal(result.error, undefined, `Cannot run ${runner}: ${result.error?.message}`);
    const output = `${result.stdout}${result.stderr}`;
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /\b(?:QCRITICAL|FAIL!)\s*:/, output);
  } finally {
    fs.rmSync(copy, { recursive: true, force: true });
  }
}

test("saved settings report failed writes, keep a backup and refuse unsafe deletes in QML", () => {
  runSavedFiles();
});

test("startup creates each required folder once with at most three processes", () => {
  runSavedFiles("startup");
});
