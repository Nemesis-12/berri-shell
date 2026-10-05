import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

test("an unchanged feed and hidden pages build no month, and a page change keeps its months", () => {
  const result = calendarOffscreen(() => {}, "qml/tst_calendar_cache.qml");
  assert.equal(result.ok, true, result.error?.message || result.output);
});
