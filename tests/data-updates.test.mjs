import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

const repo = new URL("../", import.meta.url).pathname;

// Runs complete services and views with only OS access replaced.
test("calendar details and weather views follow changed data in QML", () => {
  const result = calendarOffscreen(copy => {
    fs.cpSync(path.join(repo, "tabs/weather"), path.join(copy, "tabs/weather"), { recursive: true });
    fs.copyFileSync(path.join(repo, "services/Weather.qml"), path.join(copy, "services/Weather.qml"));
    fs.appendFileSync(path.join(copy, "services/qmldir"), "singleton Weather 1.0 Weather.qml\n");
    fs.writeFileSync(path.join(copy, "tabs/weather/qmldir"), "module qs.tabs.weather\n" +
      fs.readdirSync(path.join(copy, "tabs/weather")).filter(name => name.endsWith(".qml"))
        .map(name => `${name.slice(0, -4)} 1.0 ${name}\n`).join(""));
    fs.symlinkSync(path.join(copy, "tabs/weather"), path.join(copy, "qs/tabs/weather"));
    fs.cpSync(path.join(repo, "tests/qml-updates"), path.join(copy, "qml-updates"), { recursive: true });
  }, "qml-updates");
  assert.equal(result.ok, true, result.output);
});
