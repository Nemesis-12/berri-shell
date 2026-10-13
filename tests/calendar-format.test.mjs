import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const Format = calendarModule("CalendarFormat.js");

// Export-style calendars exercise content names, folding and nested components.
for (const [file, title] of [["google", "Planning"], ["thunderbird", "Appointment"]]) {
  const source = fs.readFileSync(new URL(`./fixtures/calendar-exports/${file}.ics`, import.meta.url), "utf8");
  for (const newline of ["\r\n", "\n"]) {
    test(`${file} export accepts grouped and extension properties with ${newline === "\n" ? "LF" : "CRLF"}`, () => {
      const text = source.replace("END:VEVENT", "item1.X-FOO;LANGUAGE=en:Kept\nX_EXPORT_ID:123\nEND:VEVENT").replaceAll("\n", newline);
      assert.equal(Format.isCompleteCalendar(text), true);
      const doc = Format.readCalendar(text);
      assert.deepEqual(Array.from(doc.items, item => item.title), [title]);
      const written = Format.writeCalendar(doc);
      assert.match(written, /item1\.X-FOO;LANGUAGE=en:Kept/i);
      assert.match(written, /X_EXPORT_ID:123/);
    });
    test(`${file} export accepts trailing blank lines and spaces with ${newline === "\n" ? "LF" : "CRLF"}`, () => {
      const text = source.replaceAll("\n", newline) + newline + " \t" + newline + "  ";
      assert.equal(Format.isCompleteCalendar(text), true);
      assert.deepEqual(Array.from(Format.readCalendar(text).items, item => item.title), [title]);
      assert.equal(Format.isCompleteCalendar(text.replace("END:VEVENT", "")), false);
      assert.equal(Format.isCompleteCalendar(text + "garbage"), false);
    });
  }
}
