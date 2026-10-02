import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { calendarModule } from "./fixtures/calendar-code.mjs";

// Exercise the view's request functions without starting the desktop shell.
function functionText(source, name) {
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
  return source.slice(start, end);
}

function sourcesView() {
  let nextRequest = 0;
  const linkInput = { text: "https://example.test/calendar" };
  const root = {
    canSubscribe: true, newColor: "blue", activeSubscription: 0,
    get subscribing() { return this.activeSubscription !== 0; },
    message: "", importNote: "", checkedLink: "",
    get link() { return linkInput.text.trim(); },
  };
  const view = vm.createContext({
    root, linkInput, colorPopover: { shown: false }, checkTimer: { stop() {} },
    Calendar: {
      subscribe() { return ++nextRequest; },
      nextCalendarColor() { return "green"; },
      calendars: [{ id: "new", name: "Current calendar", itemCount: 2 }],
    },
  });
  const source = fs.readFileSync(new URL("../tabs/calendar/CalendarSourcesView.qml", import.meta.url), "utf8");
  for (const name of ["reset", "subscribe", "onSubscribed"]) vm.runInContext(functionText(source, name), view);
  return view;
}

test("reset and a new subscribe reject a late result, even for the same URL", () => {
  const view = sourcesView();
  const url = view.root.link;
  view.subscribe();
  view.reset();
  view.linkInput.text = url;
  view.subscribe();
  view.onSubscribed(url, "old", "Old failure", 1);
  assert.equal(view.root.subscribing, true);
  assert.equal(view.root.message, "");
  assert.equal(view.linkInput.text, url);
  view.onSubscribed(url, "new", "", 2);
  assert.equal(view.root.subscribing, false);
  assert.equal(view.root.message, "subscribed · Current calendar · 2 items");
  assert.equal(view.linkInput.text, "");
  view.onSubscribed(url, "old", "Old failure", 1);
  assert.equal(view.root.message, "subscribed · Current calendar · 2 items");
});

test("reset cancels a subscribe result before another request starts", () => {
  const view = sourcesView();
  const url = view.root.link;
  view.subscribe();
  view.reset();
  view.onSubscribed(url, "new", "", 1);
  assert.equal(view.root.message, "");
  assert.equal(view.root.activeSubscription, 0);
});

test("subscribe carries distinct request ids through downloads and immediate results", () => {
  const Queries = calendarModule("CalendarQueries.js");
  const later = [];
  const downloads = [];
  const results = [];
  const subscribed = (...result) => results.push(result);
  const calendar = vm.createContext({
    Ics: calendarModule("CalendarIcs.js"), Qt: { callLater(action) { later.push(action); } },
    root: { subscribed }, subscribed, _nextSubscription: 0, _calendars: {},
    files: { download(request) { downloads.push(request); } },
  });
  const source = fs.readFileSync(new URL("../services/Calendar.qml", import.meta.url), "utf8");
  for (const name of ["subscribe", "_download", "_downloaded"]) {
    vm.runInContext(functionText(source, name).replace(/:\s*(?:string|int|void|bool|var|real)(?=\s*[,){])/g, ""), calendar);
  }
  const invalid = calendar.subscribe("bad", "blue");
  const first = calendar.subscribe("https://example.test/a", "blue");
  const second = calendar.subscribe("https://example.test/b", "green");
  assert.deepEqual([invalid, first, second], [1, 2, 3]);
  assert.deepEqual(downloads.map((request) => request.requestId), [2, 3]);
  later.shift()();
  assert.equal(results[0][3], 1);
  for (const request of downloads.reverse()) {
    calendar._downloaded(request.purpose, request.shownUrl, request.url, request.calendarId, 28, "", request.color, request.requestId);
  }
  assert.deepEqual(results.map((result) => result[3]), [1, 3, 2]);
  calendar._calendars["l-" + Queries.shortHash("https://example.test/a")] = { id: "existing" };
  const existing = calendar.subscribe("https://example.test/a", "blue");
  later.shift()();
  assert.equal(results.at(-1)[3], existing);
  assert.equal(downloads.length, 2);
});
