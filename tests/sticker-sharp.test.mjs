// Runs the real Home sticker cell on a screen with scale 2 and fake system parts.
// The cell must make its copy and decode its picture at displayed size x screen scale.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));

test("the sticker copy and picture are sharp on a screen with scale 2", t => {
  mkdirSync(path.join(root, "scratchpad"), { recursive: true });
  const run = mkdtempSync(path.join(root, "scratchpad/qml-sticker-"));
  t.after(() => rmSync(run, { recursive: true, force: true }));
  const imports = path.join(run, "imports");
  cpSync(path.join(root, "tests/qml-sticker/imports"), imports, { recursive: true });

  const copy = (from, to) => cpSync(path.join(root, from), path.join(imports, to), { recursive: true });
  copy("common", "qs/common");
  const commonTypes = readdirSync(path.join(imports, "qs/common")).filter(name => name.endsWith(".qml"));
  writeFileSync(path.join(imports, "qs/common/qmldir"),
    "module qs.common\n" + commonTypes.map(name => `${name.slice(0, -4)} 1.0 ${name}\n`).join(""));
  copy("logic", "qs/logic");
  copy("tests/qml-settings/imports/qs/services/Theme.qml", "qs/services/Theme.qml");
  copy("services/FolderRoots.qml", "qs/services/FolderRoots.qml");
  writeFileSync(path.join(imports, "qs/services/qmldir"),
    "module qs.services\nsingleton Theme 1.0 Theme.qml\nsingleton FolderRoots 1.0 FolderRoots.qml\n");
  mkdirSync(path.join(imports, "qs/tabs/home"), { recursive: true });
  copy("tabs/home/Sticker.qml", "qs/tabs/home/Sticker.qml");
  writeFileSync(path.join(imports, "qs/tabs/home/qmldir"), "module qs.tabs.home\nSticker 1.0 Sticker.qml\n");

  const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
  const result = spawnSync(runner, ["-input", path.join(root, "tests/qml-sticker"), "-import", imports], {
    encoding: "utf8",
    timeout: 60000,
    env: {
      ...process.env,
      QT_QPA_PLATFORM: "offscreen",
      QT_QUICK_BACKEND: "software",
      QT_SCALE_FACTOR: "2",
      QT_FORCE_STDERR_LOGGING: "1",
      QML_DISABLE_DISK_CACHE: "1",
    },
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
