// Run: node --test berri-shell/tests/notification-logic.test.mjs
// NotificationLogic.js is a QML library (".pragma library"), so it is evaluated in a vm context.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs
  .readFileSync(new URL("../logic/NotificationLogic.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");
const lib = vm.createContext({});
vm.runInContext(source, lib);

const plain = (value) => JSON.parse(JSON.stringify(value));
const NOW = 1_000_000;
const item = (id, appName, time, extra = {}) => ({
  id, appName, appIcon: "", summary: id, body: "", time, urgency: "normal",
  read: false, snoozedUntil: 0, actions: [], ...extra,
});
const ids = (list) => list.map((n) => n.id);

test("visible leaves out snoozed items and sorts newest first", () => {
  const all = [item("a", "X", 10), item("b", "X", 30), item("c", "Y", 20, { snoozedUntil: NOW + 5 }), item("d", "Y", 40, { snoozedUntil: NOW - 5 })];
  assert.deepEqual(ids(plain(lib.visible(all, NOW))), ["d", "b", "a"]);
  assert.equal(lib.snoozedCount(all, NOW), 1);
});

test("nextWake gives the nearest future snooze end, or 0", () => {
  const all = [item("a", "X", 1, { snoozedUntil: NOW + 50 }), item("b", "X", 2, { snoozedUntil: NOW + 10 }), item("c", "X", 3, { snoozedUntil: NOW - 1 })];
  assert.equal(lib.nextWake(all, NOW), NOW + 10);
  assert.equal(lib.nextWake([item("z", "X", 1)], NOW), 0);
});

test("groups: newest group first, counts, unread, icon from any item", () => {
  const list = [item("a", "Mail", 50), item("b", "Chat", 40, { read: true, appIcon: "chat" }), item("c", "Mail", 30, { read: true }), item("d", "Chat", 20, { appIcon: "chat" })];
  const groups = plain(lib.groupByApp(list));
  assert.deepEqual(groups.map((g) => [g.appName, g.count, g.unread]), [["Mail", 2, 1], ["Chat", 2, 1]]);
  assert.deepEqual(ids(groups[0].items), ["a", "c"]);
  assert.deepEqual(plain(lib.appList(list)), [
    { appName: "Chat", appIcon: "chat", count: 2 },
    { appName: "Mail", appIcon: "", count: 2 },
  ]);
});

test("group and cap handle names and ids inherited from Object", () => {
  const list = [item("a", "toString", 3), item("b", "__proto__", 2), item("c", "toString", 1)];
  assert.deepEqual(plain(lib.groupByApp(list)).map((g) => [g.appName, g.count]), [["toString", 2], ["__proto__", 1]]);
  assert.deepEqual(ids(plain(lib.cap([item("__proto__", "X", 1), item("new", "X", 2)], 1))), ["new"]);
});

test("cap drops the oldest read items first, then the oldest unread", () => {
  const all = [item("old-unread", "X", 1), item("old-read", "X", 2, { read: true }), item("new-read", "X", 3, { read: true }), item("new-unread", "X", 4)];
  assert.deepEqual(ids(plain(lib.cap(all, 3))), ["old-unread", "new-read", "new-unread"]);
  assert.deepEqual(ids(plain(lib.cap(all, 1))), ["new-unread"]);
  assert.equal(lib.cap(all, 10), all);
});

test("upsert replaces by id and adds new ids", () => {
  const all = [item("a", "X", 1)];
  assert.equal(lib.upsert(all, item("a", "X", 2, { summary: "new" })).length, 1);
  assert.equal(plain(lib.upsert(all, item("a", "X", 2, { summary: "new" })))[0].summary, "new");
  assert.equal(lib.upsert(all, item("b", "X", 2)).length, 2);
});

test("reload match uses server id and identity, with a unique old-file fallback", () => {
  const all = [
    item("saved", "Mail", 1, { summary: "Hello", serverId: 7 }),
    item("other", "Mail", 2, { summary: "Hello", serverId: 8 }),
  ];
  assert.equal(lib.findReloaded(all, 7, "Mail", "Hello").id, "saved");
  assert.equal(lib.findReloaded(all, 7, "Mail", "Changed"), null);
  assert.equal(lib.findReloaded(all, 9, "Mail", "Hello"), null);
  assert.equal(lib.findReloaded([all[0], item("newest", "Mail", 3, { summary: "Hello", serverId: 7 })], 7, "Mail", "Hello").id, "newest");
  assert.equal(lib.findReloaded([item("old", "Mail", 1, { summary: "Hello" })], 7, "Mail", "Hello").id, "old");
  assert.equal(lib.findReloaded([item("a", "Mail", 1, { summary: "Hello" }), item("b", "Mail", 2, { summary: "Hello" })], 7, "Mail", "Hello"), null);
});

test("updates keep read, snooze, and original time", () => {
  const old = item("saved", "Mail", 10, { read: true, snoozedUntil: NOW + 100 });
  const changed = item("saved", "Mail", 20, { summary: "New", body: "Updated" });
  assert.deepEqual(plain(lib.keepState(old, changed)), {
    ...changed, time: 10, read: true, snoozedUntil: NOW + 100,
  });
});

test("critical bypasses do not disturb", () => {
  assert.equal(lib.shouldAlert("normal", true), false);
  assert.equal(lib.shouldAlert("low", true), false);
  assert.equal(lib.shouldAlert("critical", true), true);
  assert.equal(lib.shouldAlert("normal", false), true);
});

test("pop-up queue keeps the newest waiting items", () => {
  const old = [item("a", "X", 1), item("b", "X", 2)];
  assert.deepEqual(ids(plain(lib.queuePopup(old, item("c", "X", 3), 2))), ["b", "c"]);
  assert.deepEqual(ids(old), ["a", "b"]);
});

test("waiting critical pop-ups share a hard limit and take priority over normal items", () => {
  let queue = [item("critical", "X", 0, { urgency: "critical" })];
  for (let i = 1; i <= 21; i++)
    queue = plain(lib.queuePopup(queue, item(`normal-${i}`, "X", i), 20));
  assert.deepEqual(ids(queue), ["critical", ...Array.from({ length: 19 }, (_, i) => `normal-${i + 3}`)]);
  assert.deepEqual(ids(plain(lib.queuePopup(queue, item("critical-2", "X", 22, { urgency: "critical" }), 20))),
    ["critical", ...Array.from({ length: 18 }, (_, i) => `normal-${i + 4}`), "critical-2"]);
});

test("one thousand critical pop-ups keep only the newest twenty", () => {
  let queue = [];
  for (let i = 0; i < 1000; i++)
    queue = lib.queuePopup(queue, item(`critical-${i}`, "X", i, { urgency: "critical" }), 20);
  assert.deepEqual(ids(plain(queue)), Array.from({ length: 20 }, (_, i) => `critical-${980 + i}`));
});

test("readSaved: defaults on bad input (null, text), drops bad items, clears actions", () => {
  assert.deepEqual(plain(lib.readSaved(null)), { dnd: false, items: [] });
  assert.deepEqual(plain(lib.readSaved("not an object")), { dnd: false, items: [] });
  const saved = plain(lib.readSaved({
    dnd: true,
    items: [{ id: "a", time: 5, appName: "X", urgency: "weird", actions: [{ id: "1", label: "L" }] }, { id: 7 }, null],
  }));
  assert.equal(saved.dnd, true);
  assert.equal(saved.items.length, 1);
  assert.equal(saved.items[0].urgency, "normal");
  assert.deepEqual(saved.items[0].actions, []);
  assert.equal(plain(lib.readSaved({ items: [item("a", "X", 1, { serverId: 7 })] }).items)[0].serverId, 7);
});

test("restored history cannot retain oversized sender text", () => {
  const text = "x".repeat(100 * 1024);
  const restored = plain(lib.readSaved({ items: [item("a", text, 1, { summary: text, body: text, appIcon: text })] })).items[0];
  assert.equal(restored.appName.length, 256);
  assert.equal(restored.appIcon.length, 1024);
  assert.equal(restored.summary.length, 512);
  assert.equal(restored.body.length, 4096);
  assert.equal(restored.body.slice(-3), "xxx");
});

test("saving bounded history excludes sender actions and stays below eight MiB", () => {
  const text = "\0".repeat(100 * 1024);
  const snapshot = lib.boundedItem(item("a", text, 1, { summary: text, body: text, appIcon: text,
    actions: [{ id: "open", label: "Open" }], transient: false }));
  const saved = plain(lib.savedItems([snapshot]));
  assert.equal(saved[0].summary.length, 512);
  assert.equal("actions" in saved[0], false);
  assert.equal("transient" in saved[0], false);
  const history = Array.from({ length: 200 }, (_, i) => ({ ...snapshot, id: `n${i}` }));
  const bytes = Buffer.byteLength(JSON.stringify({ dnd: false, items: lib.savedItems(history) }, null, 2));
  assert.ok(bytes < 8 * 1024 * 1024, `Saved history is ${bytes} bytes`);
});
