import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { calendarOffscreen } from "./fixtures/calendar-offscreen.mjs";

// Loads the production notifier; only saved state and external processes stay in memory.
test("round-tripped past reminders are delivered once on a revision and on first startup", () => {
  const result = calendarOffscreen(copy => {
    fs.copyFileSync(new URL("./fixtures/reminder-past.qml", import.meta.url), path.join(copy, "qml/tst_reminder_past.qml"));
    fs.mkdirSync(path.join(copy, "reminders"));
    fs.copyFileSync(new URL("../notifications/ReminderNotifier.qml", import.meta.url), path.join(copy, "reminders/ReminderNotifier.qml"));
    fs.writeFileSync(path.join(copy, "reminders/qmldir"), "module qs.reminders\nsingleton ReminderNotifier 1.0 ReminderNotifier.qml\n");
    fs.copyFileSync(new URL("./fixtures/calendar-qml/Wallpapers.qml", import.meta.url), path.join(copy, "services/Wallpapers.qml"));
    fs.appendFileSync(path.join(copy, "services/qmldir"), "singleton Wallpapers 1.0 Wallpapers.qml\n");
    fs.symlinkSync(path.join(copy, "reminders"), path.join(copy, "qs/reminders"));
    fs.writeFileSync(path.join(copy, "Quickshell/Io/Process.qml"), `import QtQuick
Item {
    property bool running: false
    property var command: []
    property var stdout: null
    property var environment: ({})
    signal exited(int code, int status)
    Component.onCompleted: {
        if (running && command[0] === "notify-send") TestIo.downloads.push(command);
    }
}
`);
  }, "qml/tst_reminder_past.qml");
  assert.equal(result.ok, true, result.output);
});
