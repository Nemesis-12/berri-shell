import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

const repo = fileURLToPath(new URL("../", import.meta.url));

// The real PanelSlide, PanelCoordinator and PanelRequests run in Qt with two fake monitors.
test("panels share one slide: close steps, dialog order, tab requests and independent monitors", () => {
  const result = calendarOffscreen(copy => {
    fs.cpSync(path.join(repo, "tests/qml-panels"), path.join(copy, "qml-panels"), { recursive: true });
  }, "qml-panels");
  assert.equal(result.ok, true, result.error?.message || result.output);
  assert.match(result.output, /Totals: \d+ passed, 0 failed, 0 skipped/);
});
