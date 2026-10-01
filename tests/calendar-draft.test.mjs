// Run: node --test tests/calendar-draft.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const plain = (value) => JSON.parse(JSON.stringify(value));
const today = new Date(2026, 8, 29);
const opening = {
  type: "event", date: "2026-09-30", time: "09:00", end: "10:00",
  color: "accent", repeat: "none", byDay: [],
};

const times = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/Times.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), times);
const parser = vm.createContext({ Times: times });
vm.runInContext(fs.readFileSync(new URL("../logic/QuickAddParser.js", import.meta.url), "utf8")
  .replace(/^\.(pragma|import).*$/gm, ""), parser);
const calendar = vm.createContext({ QuickAdd: parser, Times: times });
vm.runInContext(fs.readFileSync(new URL("../logic/CalendarDraft.js", import.meta.url), "utf8")
  .replace(/^\.(pragma|import).*$/gm, ""), calendar);

function fromText(text, { base = opening, touched = {}, current = base, clock24 = false, original = null } = {}) {
  const draft = calendar.fromText(base, touched, current, text, today, clock24);
  return {
    fields: plain(draft.fields),
    hint: plain(calendar.buildHint(draft.line, touched, draft.fields, clock24, false)),
    stored: plain(calendar.toStoredFields(draft.fields, original)),
  };
}

test("typed date, time and color fill the draft and saved fields", () => {
  const draft = fromText("Dentist fri 3pm #e93");
  assert.deepEqual(draft.stored, {
    kind: "event", title: "Dentist", date: "2026-10-02", time: "15:00", end: "16:00",
    endDate: null, color: "#ee9933", repeat: "none", byDay: [],
  });
  assert.deepEqual(draft.hint, { text: "Fri Oct 2 · 3:00 PM–4:00 PM · #e93", swatch: "#ee9933" });
});

test("a hand-set color stays when the title changes", () => {
  const draft = fromText("Dentist fri 3pm #e93", { touched: { color: true }, current: { ...opening, color: "blue" } });
  assert.equal(draft.stored.color, "blue");
  assert.deepEqual(draft.hint, { text: "Fri Oct 2 · 3:00 PM–4:00 PM", swatch: "" });
  assert.equal(fromText("Dentist", { touched: { color: true }, current: draft.fields }).stored.color, "blue");
});

test("deleting parsed parts restores the opening fields", () => {
  const previous = fromText("task Dentist fri 3pm #e93 weekly");
  const draft = fromText("Dentist", { current: previous.fields });
  assert.deepEqual(draft.stored, {
    kind: "event", title: "Dentist", date: "2026-09-30", time: "09:00", end: "10:00",
    endDate: null, color: "accent", repeat: "none", byDay: [],
  });
  assert.equal(draft.hint, null);
});

test("a reminder without a named time keeps the opening time", () => {
  const draft = fromText("remind me to call Jo tomorrow", { base: { ...opening, time: "11:00" } });
  assert.equal(draft.stored.time, "11:00");
  assert.equal(draft.stored.end, null);
  assert.deepEqual(draft.hint, { text: "Reminder · Wed Sep 30", swatch: "" });
});

test("empty reminder time saves as 09:00 and empty task time saves as null", () => {
  const base = { ...opening, time: "", end: "" };
  assert.equal(fromText("remind me to call Jo", { base }).stored.time, "09:00");
  assert.equal(fromText("task call Jo", { base }).stored.time, null);
});

test("hand-set date, time, end and repeat survive typing and deletion", () => {
  const current = { ...opening, date: "2026-11-04", time: "12:00", end: "13:00", repeat: "weekly", byDay: [3] };
  const touched = { date: true, time: true, end: true, repeat: true };
  const draft = fromText("Dentist fri 3pm daily", { current, touched });
  const deleted = fromText("Dentist", { current: draft.fields, touched });
  for (const result of [draft, deleted]) {
    assert.deepEqual(
      { date: result.stored.date, time: result.stored.time, end: result.stored.end, repeat: result.stored.repeat, byDay: result.stored.byDay },
      { date: "2026-11-04", time: "12:00", end: "13:00", repeat: "weekly", byDay: [3] },
    );
    assert.equal(result.hint, null);
  }
});

test("all-day items save without times and 24-hour hints keep their format", () => {
  const draft = fromText("Dentist fri all day");
  assert.equal(draft.stored.kind, "event");
  assert.equal(draft.stored.time, null);
  assert.equal(draft.stored.end, null);
  assert.deepEqual(draft.hint, { text: "All-day · Fri Oct 2", swatch: "" });
  assert.equal(fromText("Dentist fri 3pm", { clock24: true }).hint.text, "Fri Oct 2 · 15:00–16:00");
});

test("moving a multi-day item keeps its length across month end", () => {
  const draft = fromText("Trip fri", { original: { date: "2026-09-30", endDate: "2026-10-03" } });
  assert.equal(draft.stored.date, "2026-10-02");
  assert.equal(draft.stored.endDate, "2026-10-05");
});

test("a hand-set all-day type never hints a time that cannot be saved", () => {
  const draft = fromText("Dentist fri 3pm", { touched: { type: true }, current: { ...opening, type: "allday", time: "", end: "" } });
  assert.equal(draft.stored.time, null);
  assert.deepEqual(draft.hint, { text: "Fri Oct 2", swatch: "" });
});

test("named 09:00 fills a reminder time while a default time does not", () => {
  const base = { ...opening, time: "11:00" };
  const draft = fromText("remind me to call Jo tomorrow at 9am", { base });
  assert.equal(draft.stored.time, "09:00");
  assert.equal(draft.hint.text, "Reminder · Wed Sep 30 · 9:00 AM");
  const deleted = fromText("remind me to call Jo tomorrow", { base, current: draft.fields });
  assert.equal(deleted.stored.time, "11:00");
  assert.equal(deleted.hint.text, "Reminder · Wed Sep 30");
});

test("a hand-set event type hints the end time that will be saved", () => {
  const draft = fromText("remind me to call Jo fri 3pm", { touched: { type: true } });
  assert.equal(draft.stored.end, "10:00");
  assert.equal(draft.hint.text, "Fri Oct 2 · 3:00 PM–10:00 AM");
});

test("empty and read-only drafts have no hint", () => {
  assert.equal(fromText("").hint, null);
  const draft = calendar.fromText(opening, {}, opening, "Dentist fri 3pm", today, false);
  assert.equal(calendar.buildHint(draft.line, {}, draft.fields, false, true), null);
});

// Count real parser calls for the ticket's one-reading requirement.
test("one title change is parsed once and hint changes need no new reading", () => {
  const readTitle = parser.parse;
  let readings = 0;
  parser.parse = (...parts) => { readings++; return readTitle(...parts); };
  try {
    const draft = calendar.fromText(opening, {}, opening, "Dentist fri 3pm #e93", today, false);
    calendar.buildHint(draft.line, {}, draft.fields, false, false);
    calendar.buildHint(draft.line, { color: true }, draft.fields, true, false);
    calendar.toStoredFields(draft.fields, null);
    assert.equal(readings, 1);
  } finally {
    parser.parse = readTitle;
  }
});

// Type labels remain safe when an imported item has an unknown kind.
test("type labels keep the known labels and use Item for an unknown type", () => {
  const types = [
    { key: "event", label: "Event" }, { key: "allday", label: "All-day" },
    { key: "task", label: "Task" }, { key: "reminder", label: "Reminder" },
  ];
  assert.equal(calendar.typeLabel("event", types), "Event");
  assert.equal(calendar.typeLabel("allday", types), "All-day");
  assert.equal(calendar.typeLabel("task", types), "Task");
  assert.equal(calendar.typeLabel("reminder", types), "Reminder");
  assert.equal(calendar.typeLabel("unknown", types), "Item");
});

// The date box accepts real days and steps across month and year ends.
test("date fields reject impossible days and step across calendar edges", () => {
  assert.equal(calendar.validDate("2024-02-29"), true);
  assert.equal(calendar.validDate("2026-02-29"), false);
  assert.equal(calendar.validDate("2026-09-31"), false);
  assert.equal(calendar.validDate("2026-9-30"), false);
  assert.equal(calendar.stepDate("2026-12-31", 1), "2027-01-01");
  assert.equal(calendar.stepDate("2026-03-01", -1), "2026-02-28");
});

// The time box uses five-minute steps and starts an empty time at 09:00.
test("time fields keep five-minute steps and wrap at midnight", () => {
  assert.equal(calendar.validTime("00:00"), true);
  assert.equal(calendar.validTime("23:59"), true);
  assert.equal(calendar.validTime("24:00"), false);
  assert.equal(calendar.validTime("09:60"), false);
  assert.equal(calendar.validTime("9:00"), false);
  assert.equal(calendar.stepTime("23:55", 1), "00:00");
  assert.equal(calendar.stepTime("00:00", -1), "23:55");
  assert.equal(calendar.stepTime("", 1), "09:00");
  assert.equal(calendar.stepTime("", -1), "09:00");
});
