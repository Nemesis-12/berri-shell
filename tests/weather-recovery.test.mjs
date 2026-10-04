import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../", import.meta.url));
const fixture = path.join(repo, "tests/fixtures");
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

// Replaces only Quickshell boundaries, keeping service functions, bindings, and timers intact.
function runWeather(scenario) {
  fs.mkdirSync(path.join(repo, "scratchpad"), { recursive: true });
  const folder = fs.mkdtempSync(path.join(repo, "scratchpad/weather-test-"));
  try {
    fs.cpSync(path.join(fixture, "weather-io"), path.join(folder, "Io"), { recursive: true });
    const source = fs.readFileSync(path.join(repo, "services/Weather.qml"), "utf8")
      .replace(/^pragma Singleton\n/, "")
      .replace(/^import Quickshell\n/m, 'import "Io"\n')
      .replace(/^import Quickshell.Io\n/m, "")
      .replace('"../logic/WeatherParse.js"', JSON.stringify(path.join(repo, "logic/WeatherParse.js")))
      .replace('Quickshell.env("HOME")', '"/synthetic-home"');
    fs.writeFileSync(path.join(folder, "WeatherUnderTest.qml"), source);
    const config = { scenario, forecast, timeScale: Number(process.env.WEATHER_TEST_TIME_SCALE || 0.01) };
    const runner = fs.readFileSync(path.join(fixture, "weather-recovery.qml"), "utf8")
      .replace("TEST_CONFIG", JSON.stringify(config));
    const entry = path.join(folder, "test.qml");
    fs.writeFileSync(entry, runner);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1" };
    delete env.LD_LIBRARY_PATH;
    const result = spawnSync("qml6", [entry], { env, encoding: "utf8", timeout: 75000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr, /Weather recovered with 18 degrees/);
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
}

test("weather recovers within 70 seconds after the first location call fails", () => {
  runWeather("location");
});
