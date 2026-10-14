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
    fs.copyFileSync(path.join(repo, "services/StandardColorMotion.qml"), path.join(folder, "services/StandardColorMotion.qml"));
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
    const result = spawnSync("qml6", ["-I", folder, path.join(folder, "test.qml")], { env, encoding: "utf8", timeout: 180000 });
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

test("the weather day rows and crossfade keep the selected date across midnight and a shorter forecast", () => {
  const result = runViews(folder => {
    fs.copyFileSync(path.join(repo, "tests/fixtures/weather-selection.qml"), path.join(folder, "test.qml"));
    const weather = path.join(folder, "services/Weather.qml");
    fs.writeFileSync(weather, fs.readFileSync(weather, "utf8")
      .replace("readonly property var days: []", "property var days: []")
      .replace("    function refresh()", "    function stripHours(i, now) { return []; }\n    function refresh()"));
    const theme = path.join(folder, "services/Theme.qml");
    fs.writeFileSync(theme, fs.readFileSync(theme, "utf8").replace("QtObject {", `QtObject {
    readonly property color border: "#332f3b"
    readonly property color card: "#211d28"
    readonly property color sunk: "#17141d"
    readonly property color selectionSoft: "#342417"`));
  });
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.match(output, /Weather selection checks passed/);
  assert.doesNotMatch(output, /Warning|Error|ReferenceError|TypeError/i);
});

test("unknown and offline weather uses placeholders in Home, the card, readouts, hours and day rows", () => {
  const result = runViews(folder => {
    fs.copyFileSync(path.join(repo, "tests/fixtures/weather-missing.qml"), path.join(folder, "test.qml"));
    const weather = path.join(folder, "services/Weather.qml");
    fs.writeFileSync(weather, fs.readFileSync(weather, "utf8")
      .replace("return { tempC: 24, feelsLikeC: 25, maxC: 26, minC: 17, code: 3, isDay: true };",
               "return { tempC: null, feelsLikeC: null, maxC: null, minC: null, code: null, isDay: true, humidity: null, dewPointC: null, windKmh: null, windDirection: '', gustKmh: null, precipProbability: null, precipMm: null, uvIndex: null, uvLabel: '', sunrise: '', sunset: '' };")
      .replace("    function refresh()", `    function stripHours(i, now) {
        return [{ time: "2026-03-08T02:00", tempC: null, code: null, isDay: null, precipProbability: null }];
    }
    function refresh()`));
    const theme = path.join(folder, "services/Theme.qml");
    fs.writeFileSync(theme, fs.readFileSync(theme, "utf8").replace("QtObject {", `QtObject {
    readonly property color card: "#211d28"
    readonly property color selectionSoft: "#342417"`));
  });
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.match(output, /Weather missing view checks passed/);
  assert.doesNotMatch(output, /Warning|Error|ReferenceError|TypeError/i);
});
