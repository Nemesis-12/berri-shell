import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

test("month chips open and drag, blank cells select, and a reopen on a later day selects it", () => {
  const result = calendarOffscreen(() => {}, "qml/tst_calendar_days.qml");
  assert.equal(result.ok, true, result.error?.message || result.output);
});
