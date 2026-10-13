import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const source = fs.readFileSync(new URL("../notifications/NotificationPopup.qml", import.meta.url), "utf8");

// Names that shell.qml and the maintainer's checks may use. Everything else starts with "_".
const publicNames = [
  "anchorRect", "dpr", "dashboardOpen", "screenName", "blocked",
  "openAlertsRequested", "active", "cardMaxWidth", "cardX", "cardY", "cardWidth", "cardHeight",
];

test("the pop-up exposes only its small host interface", () => {
  const declared = [...source.matchAll(/^ {4}(?:required |readonly )?(?:property \w+|signal|function) (\w+)/gm)].map((m) => m[1]);
  const exposed = declared.filter((name) => !name.startsWith("_"));
  assert.deepEqual([...exposed].sort(), [...publicNames].sort());
});
