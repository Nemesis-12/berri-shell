import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../../", import.meta.url));

// Loads complete calendar QML and JS files with only OS access replaced.
export function calendarOffscreen(change = () => {}, input = "qml") {
  const scratch = path.join(repo, "scratchpad");
  fs.mkdirSync(scratch, { recursive: true });
  const copy = fs.mkdtempSync(path.join(scratch, "calendar-qml-"));
  try {
    for (const folder of ["logic", "common", "picker", "pill", "tabs/calendar"])
      fs.cpSync(path.join(repo, folder), path.join(copy, folder), { recursive: true });
    fs.mkdirSync(path.join(copy, "services"));
    for (const name of ["Calendar", "CalendarFiles", "Theme", "Clock"])
      fs.copyFileSync(path.join(repo, `services/${name}.qml`), path.join(copy, `services/${name}.qml`));
    fs.cpSync(path.join(repo, "tests/fixtures/calendar-qml/Quickshell"), path.join(copy, "Quickshell"), { recursive: true });
    fs.copyFileSync(path.join(repo, "tests/fixtures/calendar-qml/SavedState.qml"), path.join(copy, "common/SavedState.qml"));
    fs.cpSync(path.join(repo, "tests/qml"), path.join(copy, "qml"), { recursive: true });
    fs.mkdirSync(path.join(copy, "qs"));
    fs.symlinkSync(path.join(copy, "logic"), path.join(copy, "qs/logic"));
    for (const folder of ["common", "picker", "pill", "services", "tabs/calendar"]) {
      const lines = [`module qs.${folder.replaceAll("/", ".")}`];
      for (const name of fs.readdirSync(path.join(copy, folder)).filter(name => name.endsWith(".qml"))) {
        const source = fs.readFileSync(path.join(copy, folder, name), "utf8");
        lines.push(`${/^pragma Singleton/m.test(source) ? "singleton " : ""}${name.slice(0, -4)} 1.0 ${name}`);
      }
      fs.writeFileSync(path.join(copy, folder, "qmldir"), lines.join("\n") + "\n");
      const link = path.join(copy, "qs", folder);
      fs.mkdirSync(path.dirname(link), { recursive: true });
      fs.symlinkSync(path.join(copy, folder), link);
    }
    fs.mkdirSync(path.join(copy, "qs/notifications"));
    fs.writeFileSync(path.join(copy, "qs/notifications/qmldir"), "module qs.notifications\nScope 1.0 ../../Quickshell/Scope.qml\n");
    change(copy);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QML_DISABLE_DISK_CACHE: "1" };
    delete env.LD_LIBRARY_PATH;
    const result = spawnSync(process.env.QMLTESTRUNNER || "/usr/lib/qt6/bin/qmltestrunner",
      ["-import", copy, "-input", path.join(copy, input)], { cwd: copy, env, encoding: "utf8", timeout: 30000 });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.error)
      throw new Error(`qmltestrunner failed: ${result.error.message}\n${output}`);
    // Connections can emit a warning while the component still loads.
    const ok = result.status === 0 && !/\b(?:QWARN|QCRITICAL|FAIL!)\s*:/.test(output);
    return { ok, output, error: result.error };
  } finally {
    fs.rmSync(copy, { recursive: true, force: true });
  }
}
