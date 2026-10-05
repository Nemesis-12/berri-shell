import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const logic = new URL("../logic/", import.meta.url);
const file = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nSUMMARY:A\r\nDTSTART;VALUE=DATE:20261005\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
const record = { uid: "a", kind: "event", title: "A", date: "2026-10-05" };

// Copies the logic folder, adds one field to blankItem in the copy and loads CalendarFormat.js from it.
function formatWithFactoryField(addField) {
  const copy = fs.mkdtempSync(path.join(os.tmpdir(), "item-factory-"));
  try {
    fs.cpSync(logic, copy, { recursive: true });
    const target = path.join(copy, "CalendarItems.js");
    const source = fs.readFileSync(target, "utf8");
    const marker = 'raw: [], rawChildren: []\n    };\n}';
    assert.ok(source.includes(marker), "blankItem literal not found");
    if (addField) fs.writeFileSync(target, source.replace(marker, 'raw: [], rawChildren: [],\n        testField: "from the factory"\n    };\n}'));
    return calendarModule("CalendarFormat.js", pathToFileURL(copy + "/"));
  } finally {
    fs.rmSync(copy, { recursive: true, force: true });
  }
}

test("a field added to the item factory alone shows in the file reader and the record reader", () => {
  const before = formatWithFactoryField(false);
  assert.equal(before.readCalendar(file).items[0].testField, undefined);
  assert.equal(before.expandCompactItem(record).testField, undefined);

  const after = formatWithFactoryField(true);
  assert.equal(after.readCalendar(file).items[0].testField, "from the factory");
  assert.equal(after.expandCompactItem(record).testField, "from the factory");
});
