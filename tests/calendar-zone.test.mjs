import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

test("QML reads and writes named calendar zones with the production converter", () => {
  const env = { ...process.env, TZ: "America/Chicago", QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1" };
  delete env.LD_LIBRARY_PATH;
  const result = spawnSync(process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner",
    ["-input", fileURLToPath(new URL("./fixtures/calendar-zone-reader.qml", import.meta.url))],
    { env, encoding: "utf8", timeout: 30000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});
