import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

// Change only the isolated copy used by the offscreen runner.
function replaceInCopy(copy, file, before, after) {
  const target = path.join(copy, file);
  const source = fs.readFileSync(target, "utf8");
  assert.ok(source.includes(before), `Missing mutation target in ${file}`);
  fs.writeFileSync(target, source.replace(before, after));
}

test("complete calendar service and component behavior passes offscreen", () => {
  const result = calendarOffscreen();
  assert.equal(result.ok, true, result.error?.message || result.output);
});

test("closing braces in comments leave calendar behavior unchanged", () => {
  const result = calendarOffscreen(copy => {
    for (const [file, opening] of [
      ["services/Calendar.qml", "function _rebuild(): void {"],
      ["tabs/calendar/CalendarSourcesView.qml", "function reset() {"],
      ["logic/CalendarMonths.js", "function createMonthCache(calendars) {"],
    ]) replaceInCopy(copy, file, opening, `${opening}\n    // A comment can contain }\n    /* A block comment can contain } too. */`);
  });
  assert.equal(result.ok, true, result.error?.message || result.output);
});

test("a renamed component signal fails the offscreen load check", () => {
  const result = calendarOffscreen(copy => {
    replaceInCopy(copy, "tabs/calendar/CalendarDayPanel.qml", "signal calendarsRequested", "signal calendarListRequested");
  }, "qml/tst_calendar_components.qml");
  assert.equal(result.ok, false, result.output);
  assert.match(result.output, /onCalendarsRequested|calendarsRequested/);
});

test("a renamed service signal fails the offscreen connection check", () => {
  const result = calendarOffscreen(copy => {
    replaceInCopy(copy, "services/Calendar.qml", "signal subscribed(string url, string id, string error, int requestId)", "signal subscriptionFinished(string url, string id, string error, int requestId)");
  }, "qml/tst_calendar_components.qml");
  assert.equal(result.ok, false, result.output);
  assert.match(result.output, /onSubscribed/);
});

test("an unset required row property fails the offscreen load check", () => {
  const result = calendarOffscreen(copy => {
    replaceInCopy(copy, "tabs/calendar/DayItemRow.qml", "required property string title", "required property string title\n    required property string missingForTest");
  }, "qml/tst_calendar_components.qml");
  assert.equal(result.ok, false, result.output);
  assert.match(result.output, /Required property missingForTest was not initialized/);
});
