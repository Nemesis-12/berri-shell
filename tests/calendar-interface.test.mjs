import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

// Exercises the operations used by file and link helpers with real calendar state.
test("calendar helper operations preserve file text, import identity and link refresh results", () => {
  const result = calendarOffscreen(() => {}, "qml/tst_calendar_interface.qml");
  assert.equal(result.ok, true, result.output);
});
