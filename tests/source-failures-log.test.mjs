// Run: node --test tests/source-failures-log.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));
const forecast = {
  current: { time: "2026-09-30T06:15", temperature_2m: 17.5, apparent_temperature: 19.5,
    relative_humidity_2m: 96, dew_point_2m: 16.8, weather_code: 2, is_day: 0,
    wind_speed_10m: 2.9, wind_direction_10m: 315, wind_gusts_10m: 8.6, surface_pressure: 1004.9 },
  hourly: { time: ["2026-09-30T06:00"], weather_code: [3], is_day: [1], temperature_2m: [18.4],
    precipitation_probability: [10], uv_index: [6.4] },
  daily: { time: ["2026-09-30"], weather_code: [3], temperature_2m_min: [15.2], temperature_2m_max: [22.6],
    precipitation_probability_max: [20], precipitation_sum: [0.34], sunrise: ["2026-09-30T07:30"],
    sunset: ["2026-09-30T19:43"], daylight_duration: [43980], uv_index_max: [5.2],
    wind_speed_10m_max: [14], wind_gusts_10m_max: [30], apparent_temperature_max: [23],
    relative_humidity_2m_mean: [80], dew_point_2m_mean: [15], wind_direction_10m_dominant: [0],
    surface_pressure_mean: [1005] },
};
const SECRET = "Bearer sk-SECRET https://api.example.test/?token=TOKEN123 private-message-text";
const ok = (text) => ({ text, code: 0 });

// Runs a real service file with synthetic answers. Returns the log lines it wrote.
function run(service, file, rounds) {
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const folder = fs.mkdtempSync(path.join(repo, "scratchpad/failure-log-"));
  try {
    fs.cpSync(path.join(repo, "tests/fixtures/weather-io"), path.join(folder, "Io"), { recursive: true });
    const source = fs.readFileSync(path.join(repo, "services", file), "utf8")
      .replace(/^pragma Singleton\n/, "")
      .replace(/^import Quickshell\n/m, 'import "Io"\n')
      .replace(/^import Quickshell.Io\n/m, "")
      .replace(/^import qs\.common\n/m, "")
      .replace(/Quickshell\.shellPath\(/g, "(")
      .replace('Quickshell.env("HOME")', '"/synthetic-home"')
      .replace(/"\.\.\/logic\/([A-Za-z]+\.js)"/g, (_, name) => JSON.stringify(path.join(repo, "logic", name)));
    fs.writeFileSync(path.join(folder, "ServiceUnderTest.qml"), source);
    const runner = fs.readFileSync(path.join(repo, "tests/fixtures/source-failures.qml"), "utf8")
      .replace("TEST_CONFIG", JSON.stringify({ service, rounds }));
    const entry = path.join(folder, "test.qml");
    fs.writeFileSync(entry, runner);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1" };
    delete env.LD_LIBRARY_PATH;
    const result = spawnSync("qml6", [entry], { env, encoding: "utf8", timeout: 30000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr + result.stdout, /Failure log checks passed/);
    return (result.stderr + result.stdout).split("\n").filter(l => l.includes("berri-shell:"));
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
}

const goodUsage = ok(JSON.stringify({ claude: { session: { percent: 42, resetsAt: "2026-10-04T20:00:00Z" } } }));

test("usage with malformed output logs one line and a second failure adds none", () => {
  const lines = run("usage", "AgentUsage.qml", [
    { "*": goodUsage }, { "*": ok(SECRET) }, { "*": ok("") }, { "*": ok("null") }]);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /berri-shell: usage data failed \(bad output\)$/);
});

test("usage failure lines hold no response text", () => {
  const lines = run("usage", "AgentUsage.qml", [{ "*": goodUsage }, { "*": ok(SECRET) }]);
  assert.equal(lines.join("\n").match(/sk-SECRET|TOKEN123|https|private/), null);
});

test("each code source logs its own line once", () => {
  const good = ok(JSON.stringify({ generatedAt: "g1", days: [{ date: "2026-10-01" }], models: { claude: [], codex: [] }, usage: {} }));
  const lines = run("code", "CodeData.qml", [
    { "code-stats": good, "*": ok("") },
    { "*": ok(SECRET) }, { "*": ok("") }, { "*": ok("{oops") }]);
  const names = lines.map(l => l.replace(/^.*(berri-shell: )/, "$1")).sort();
  assert.deepEqual(names, [
    "berri-shell: code commits data failed (no output)",
    "berri-shell: code github data failed (no output)",
    "berri-shell: code stats data failed (bad output)"]);
});

test("weather logs one line for offline and bad data inside the period", () => {
  const lines = run("weather", "Weather.qml", [
    { "*": ok(JSON.stringify(forecast)) },
    { "*": { text: "", code: 22 } }, { "*": { text: SECRET, code: 22 } },
    { "*": ok(SECRET) }, { "*": ok("") }]);
  assert.equal(lines.length, 1);
  assert.match(lines[0], /berri-shell: weather data failed \(offline\)$/);
});

test("weather names bad data for an unreadable or empty answer with a good exit code", () => {
  for (const answer of [SECRET, ""]) {
    const lines = run("weather", "Weather.qml", [{ "*": ok(JSON.stringify(forecast)) }, { "*": ok(answer) }]);
    assert.equal(lines.length, 1);
    assert.match(lines[0], /berri-shell: weather data failed \(bad data\)$/);
  }
});
