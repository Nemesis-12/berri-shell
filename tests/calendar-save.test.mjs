import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { calendarCode } from "./fixtures/calendar-code.mjs";

const source = fs.readFileSync(new URL("../services/Calendar.qml", import.meta.url), "utf8");

function loadFunction(context, name) {
  const start = source.indexOf("function " + name + "(");
  assert.ok(start >= 0, "Missing function " + name);
  const opening = source.indexOf("{", start);
  let depth = 1;
  let end = opening + 1;
  while (depth && end < source.length) {
    if (source[end] === "{") depth++;
    if (source[end] === "}") depth--;
    end++;
  }
  const code = source.slice(start, end).replace(/:\s*(?:string|int|void|bool|var|real)(?=\s*[,){])/g, "");
  vm.runInContext(code, context);
}

function calendarWithWrite(ok) {
  const Ics = calendarCode();
  const path = "/test/berri.ics";
  const original = Ics.emptyCalendar();
  original.items.push(Ics.makeItem({ uid: "saved", title: "Before", date: "2026-10-01" }));
  const text = Ics.writeCalendar(original);
  const calendar = { id: "berri", name: "berri", kind: "local", color: "accent", hidden: false,
    path, text, document: Ics.readCalendar(text), loaded: true };
  const writes = [];
  const errors = [];
  const context = vm.createContext({
    Ics, _calendars: { berri: calendar }, _order: ["berri"], defaultPath: path,
    _projection: Ics.projectCalendars([calendar]), _localZone: undefined,
    _cache: {}, revision: 0, lastError: "", saveFailed: message => errors.push(message),
    files: { write(file, contents, done) { writes.push([file, contents]); done(ok, ok ? "" : "Permission denied"); } },
  });
  for (const name of ["_cleanDates", "_idOfPath", "_locate", "_rebuild", "_commit", "update", "add"]) loadFunction(context, name);
  return { context, calendar, original: text, writes, errors, Ics };
}

test("failed edit restores the saved item and reports the write error", () => {
  const { context, calendar, original, writes, errors, Ics } = calendarWithWrite(false);
  assert.equal(context.update(Ics.itemKey("berri", "saved"), { title: "After" }), false);
  assert.equal(calendar.text, original);
  assert.equal(calendar.document.items[0].title, "Before");
  assert.equal(context._projection.items[0].title, "Before");
  assert.equal(context.revision, 1);
  assert.equal(writes.length, 1);
  assert.match(writes[0][1], /SUMMARY:After/);
  assert.deepEqual(errors, ["Could not save berri: Permission denied"]);
});

test("failed new item is absent, while a successful edit reaches the view", () => {
  const failed = calendarWithWrite(false);
  assert.equal(failed.context.add({ title: "New", date: "2026-10-02" }), "");
  assert.equal(failed.calendar.text, failed.original);
  assert.deepEqual(Array.from(failed.calendar.document.items, item => item.title), ["Before"]);
  assert.deepEqual(Array.from(failed.context._projection.items, item => item.title), ["Before"]);

  const saved = calendarWithWrite(true);
  assert.equal(saved.context.update(saved.Ics.itemKey("berri", "saved"), { title: "After" }), true);
  assert.equal(saved.calendar.document.items[0].title, "After");
  assert.equal(saved.context._projection.items[0].title, "After");
  assert.match(saved.calendar.text, /SUMMARY:After/);
  assert.deepEqual(saved.errors, []);
});
