import { test } from "node:test";
import assert from "node:assert/strict";
import { calendarModule } from "./fixtures/calendar-code.mjs";

const Items = calendarModule("CalendarItems.js");
const Delivery = calendarModule("ReminderDelivery.js");
const plain = (value) => JSON.parse(JSON.stringify(value));
const reminder = (fields) => Items.makeItem({ kind: "reminder", title: "x", ...fields });

test("a title that looks like an option stays the title and the time stays the body", () => {
  for (const [title, time] of [["--version", "09:00"], ["-h", "10:00"]]) {
    const argv = plain(Delivery.notifyCommand({ title, time }));
    assert.deepEqual(argv.slice(-3), ["--", title, time]);
    assert.equal(argv.indexOf("--"), argv.length - 3, "no option may follow the separator");
  }
  assert.deepEqual(plain(Delivery.notifyCommand({ title: "", time: "10:00" })).slice(-2), ["Reminder", "10:00"]);
});

test("a reminder sends the two actions the pop-up can show, and both are handled", () => {
  const argv = plain(Delivery.notifyCommand({ title: "Call", time: "10:00" }));
  const actions = argv.flatMap((arg, i) => (argv[i - 1] === "-A" ? [arg] : []));
  assert.deepEqual(actions, ["plus15=+15m", "done=Done"]);
  assert.ok(actions.length <= Delivery.popupActionLimit);
});

test("a failed delivery makes the reminder due again and keeps its old check time safe", () => {
  const at = (h, m) => new Date(2026, 9, 5, h, m).getTime();
  const items = [reminder({ uid: "r1", title: "Call", date: "2026-10-05", time: "10:00" })];
  const [due] = Items.dueBetween(items, at(9, 0), at(10, 1));
  const key = Items.itemKey(due.calendarId, due.uid) + "|" + due.dueMs;
  const state = { lastCheck: at(10, 1), shown: [key, "other|1"] };
  const next = plain(Delivery.afterFailedDelivery(state, key, due.dueMs));
  assert.deepEqual(next.shown, ["other|1"]);
  assert.equal(next.lastCheck, due.dueMs - 1);
  assert.equal(Items.dueBetween(items, next.lastCheck, at(10, 2)).length, 1);
  // A failure never moves the check time forward.
  assert.equal(Delivery.afterFailedDelivery({ lastCheck: 5, shown: [key] }, key, due.dueMs).lastCheck, 5);
});

test("a retry waits instead of firing at once", () => {
  assert.equal(Delivery.nextWake(1000, 5000, 30000), 35000);
  assert.equal(Delivery.nextWake(9000, 5000, 30000), 9000);
  assert.equal(Delivery.nextWake(0, 5000, 30000), 0);
});

test("snooze counts from the alert time, across midnight, and clears the alarm offset", () => {
  // Now is Oct 1 23:40. The reminder is Oct 2 00:10 with a 30 minute alarm: it alerts now.
  const target = plain(Items.snoozeReminder("00:10", "2026-10-02", 30, 15, "2026-10-01", "23:40"));
  assert.deepEqual(target, { date: "2026-10-01", time: "23:55", alarmMinutes: 0 });
  // The alert time lies in the past: count from now.
  assert.deepEqual(plain(Items.snoozeReminder("10:00", "2026-10-01", 30, 15, "2026-10-01", "11:00")),
    { date: "2026-10-01", time: "11:15", alarmMinutes: 0 });
  // No alarm: same as before, and the result crosses midnight.
  assert.deepEqual(plain(Items.snoozeReminder("23:50", "2026-10-01", 0, 15, "2026-09-01", "10:00")),
    { date: "2026-10-02", time: "00:05", alarmMinutes: 0 });
  // One day keeps the clock time and the alarm.
  assert.deepEqual(plain(Items.snoozeReminder("00:10", "2026-10-02", 30, "1d", "2026-10-01", "23:40")),
    { date: "2026-10-03", time: "00:10", alarmMinutes: 30 });
});

test("an imported alarm of 60,000 weeks is ignored and the scan stays fast", () => {
  const weeks = 60000 * 7 * 24 * 60;
  const items = [
    reminder({ uid: "big", title: "Big", date: "2026-10-05", time: "10:00", repeat: "daily", alarmMinutes: weeks }),
    reminder({ uid: "ok", title: "Ok", date: "2026-10-05", time: "10:00", alarmMinutes: 15 }),
  ];
  const from = new Date(2026, 9, 5, 9, 0).getTime();
  const to = new Date(2026, 9, 5, 10, 0).getTime();
  const started = performance.now();
  const due = Items.dueBetween(items, from, to);
  const next = Items.nextDueMs(items, from, 400);
  const took = performance.now() - started;
  assert.deepEqual(plain(due.map((d) => d.uid)), ["ok"]);
  assert.equal(next, new Date(2026, 9, 5, 9, 45).getTime());
  assert.ok(took < 5, `scan took ${took} ms`);
});
