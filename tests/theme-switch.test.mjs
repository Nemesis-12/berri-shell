import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

const repo = fileURLToPath(new URL("../", import.meta.url));

// The real Theme and tray style run in Qt with only OS access replaced.
test("theme switches start one wallpaper transition and the tray uses the button hover fill", () => {
  const result = calendarOffscreen(copy => {
    fs.cpSync(path.join(repo, "tests/qml-theme"), path.join(copy, "qml-theme"), { recursive: true });
  }, "qml-theme");
  assert.equal(result.ok, true, result.error?.message || result.output);
  assert.match(result.output, /Totals: \d+ passed, 0 failed, 0 skipped/);
});
