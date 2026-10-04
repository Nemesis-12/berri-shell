// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const lib = calendarModule("CalendarSave.js");

test("a saved write keeps the new text and has no error", () => {
  assert.deepEqual({ ...lib.writeOutcome(true, "", "Could not save berri", "old", "new") },
    { saved: true, text: "new", error: "" });
});

test("a failed write restores the old text and names the cause", () => {
  assert.deepEqual({ ...lib.writeOutcome(false, "Permission denied", "Could not save berri", "old", "new") },
    { saved: false, text: "old", error: "Could not save berri: Permission denied" });
});
