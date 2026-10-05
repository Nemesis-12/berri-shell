import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

test("add, update and remove save, then rebuild, then signal; a failed save undoes, rebuilds, then reports", () => {
  const result = calendarOffscreen(() => {}, "qml/tst_calendar_order.qml");
  assert.equal(result.ok, true, result.error?.message || result.output);
});
