import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

test("an unreadable calendar refuses edits and a removed subscription ignores late downloads", () => {
  const result = calendarOffscreen(() => {}, "qml/tst_calendar_read_safety.qml");
  assert.equal(result.ok, true, result.error?.message || result.output);
});
