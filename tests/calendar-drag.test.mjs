import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const Drag = calendarModule("CalendarDrag.js");

test("a 4-pixel move does not start a drag and a 6-pixel move does", () => {
  assert.equal(Drag.pastThreshold(4, 0), false);
  assert.equal(Drag.pastThreshold(0, -4), false);
  assert.equal(Drag.pastThreshold(6, 0), true);
  assert.equal(Drag.pastThreshold(-3, 5), true);
});

test("only the shared drag function measures the distance of a calendar drag", () => {
  const dir = new URL("../tabs/calendar/", import.meta.url);
  const sources = fs.readdirSync(dir).filter((name) => name.endsWith(".qml"))
    .map((name) => [name, fs.readFileSync(new URL(name, dir), "utf8")]);
  const calculations = sources.filter(([, text]) => /Math\.hypot|dragThreshold/.test(text)).map(([name]) => name);
  assert.deepEqual(calculations, []);
  const users = sources.filter(([, text]) => /Drag\.pastThreshold\(/.test(text)).map(([name]) => name).sort();
  assert.deepEqual(users, ["CalendarMonthGrid.qml", "DayItemRow.qml"]);
});
