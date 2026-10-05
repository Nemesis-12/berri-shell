// Source scans for ticket 75: one slide operation, and no tab state in the pill or the shell.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = fileURLToPath(new URL("../", import.meta.url));
const sources = ["common", "dashboard", "picker", "pill", "tabs", "notifications"]
  .flatMap(folder => fs.readdirSync(path.join(repo, folder), { recursive: true })
    .filter(name => name.endsWith(".qml")).map(name => path.join(folder, name)))
  .concat("shell.qml");
const read = file => fs.readFileSync(path.join(repo, file), "utf8");

test("only PanelSlide moves a panel in a straight line and starts a close", () => {
  const users = sources.filter(file => /slideDurationMs|startClose/.test(read(file)));
  assert.deepEqual(users, [path.join("common", "PanelSlide.qml")]);
});

test("the pill and the shell hold no tab-specific state", () => {
  const tabState = /wifiPassword|textEntry|calendarTab|importPending|chooseImportFile|addPending/;
  const hits = sources.filter(file => /^(pill|dashboard)\/|^shell\.qml$/.test(file.replaceAll("\\", "/")) && tabState.test(read(file)));
  assert.deepEqual(hits, []);
});
