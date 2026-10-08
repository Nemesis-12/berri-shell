import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

// Load the real store and views in Qt, with only OS services replaced.
test("notifications stay bounded and current in the QML engine", (t) => {
  const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
  if (!fs.existsSync(runner)) return t.skip("qmltestrunner is not installed");
  const repo = fileURLToPath(new URL("../", import.meta.url));
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const dir = fs.mkdtempSync(path.join(repo, "scratchpad", "notification-qml-"));
  fs.cpSync(path.join(repo, "tests/fixtures/notification-qml"), dir, { recursive: true });
  for (const name of ["logic", "notifications", "pill", "tabs/alerts"]) {
    fs.cpSync(path.join(repo, name), path.join(dir, "qs", name), { recursive: true });
  }
  const common = ["Icon", "PanelShadow", "ColorFade", "Fade", "HoverButton", "SpringMotion", "StandardMotion", "EmphasizedMotion", "ToggleSwitch"];
  for (const name of common) {
    fs.copyFileSync(path.join(repo, "common", `${name}.qml`), path.join(dir, "qs/common", `${name}.qml`));
  }
  fs.copyFileSync(path.join(repo, "common/Icons.js"), path.join(dir, "qs/common/Icons.js"));
  fs.writeFileSync(path.join(dir, "qs/common/qmldir"), "module qs.common\n" +
    [...common, "AlertsAppIcon"].map((name) => `${name} 1.0 ${name}.qml`).join("\n"));
  fs.writeFileSync(path.join(dir, "qs/notifications/qmldir"),
    "module qs.notifications\nsingleton Notifications 1.0 Notifications.qml\n");
  const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QSG_RHI_BACKEND: "software", XDG_CACHE_HOME: path.join(dir, "cache") };
  delete env.LD_LIBRARY_PATH;
  const result = spawnSync(runner, ["-input", dir, "-import", dir], { env, encoding: "utf8", timeout: 60000 });
  const output = result.stdout + result.stderr;
  fs.writeFileSync(path.join(dir, "result.txt"), output);
  t.diagnostic(output.trim());
  assert.equal(result.status, 0, `QML test failed. Output: ${dir}/result.txt\n${output}`);
});
