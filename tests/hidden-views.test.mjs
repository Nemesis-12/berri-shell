// Runs the real lists, Code tab and shared counters with fake system objects. It never starts a shell instance.
import { test } from "node:test";
import assert from "node:assert/strict";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));

test("hidden views stop work and shared requests wait for the last owner", t => {
  const runner = process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner";
  mkdirSync(path.join(root, "scratchpad"), { recursive: true });
  const run = mkdtempSync(path.join(root, "scratchpad/qml-hidden-"));
  t.after(() => rmSync(run, { recursive: true, force: true }));
  const imports = path.join(run, "imports");
  cpSync(path.join(root, "tests/qml-playback/imports"), imports, { recursive: true });
  cpSync(path.join(root, "tests/qml-requests/overlay"), imports, { recursive: true });

  for (const folder of ["common", "tabs/code", "tabs/system", "logic"]) {
    const target = path.join(imports, "qs", folder);
    cpSync(path.join(root, folder), target, { recursive: true });
    if (folder === "logic") continue;
    const types = readdirSync(target).filter(name => name.endsWith(".qml"));
    writeFileSync(path.join(target, "qmldir"),
      `module qs.${folder.replaceAll("/", ".")}\n` +
      types.map(name => `${name.slice(0, -4)} 1.0 ${name}\n`).join(""));
  }
  const services = ["MediaPlayer", "Brightness", "AgentUsage", "CodeData", "RadioRequests"];
  for (const name of services) {
    cpSync(path.join(root, `services/${name}.qml`), path.join(imports, `qs/services/${name}.qml`));
  }
  cpSync(path.join(root, "services/CachedSource.qml"), path.join(imports, "qs/services/CachedSource.qml"));
  writeFileSync(path.join(imports, "qs/services/qmldir"),
    "module qs.services\nsingleton Theme 1.0 Theme.qml\nCachedSource 1.0 CachedSource.qml\n" +
    services.map(name => `singleton ${name} 1.0 ${name}.qml\n`).join(""));
  // The services import "../logic/...", so the logic folder sits next to them.
  cpSync(path.join(root, "logic"), path.join(imports, "qs/logic"), { recursive: true });

  const result = spawnSync(runner, ["-input", path.join(root, "tests/qml-requests"), "-import", imports], {
    encoding: "utf8",
    timeout: 90000,
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
