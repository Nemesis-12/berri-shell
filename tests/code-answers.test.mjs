import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const answers = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL("../logic/CodeAnswers.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, ""), answers);

test("Code source checks require the fields their views read", () => {
  const bucket = { tokens: 0, cost: 0 };
  const usage = { claude: { today: bucket, week: bucket, month: bucket },
    codex: { today: bucket, week: bucket, month: bucket } };
  const stats = { generatedAt: "2026-10-14T12:00:00Z", days: [],
    models: { claude: [], codex: [] }, usage };
  assert.equal(answers.stats(stats), true);
  assert.equal(answers.stats({ ...stats, days: undefined }), false);
  assert.equal(answers.stats({ ...stats, usage: {} }), false);
});

test("GitHub and commit source checks reject incomplete lists", () => {
  const github = { fetchedAt: "2026-10-14T12:00:00Z", total: 0, days: [], years: [] };
  assert.equal(answers.github(github), true);
  assert.equal(answers.github({ ...github, total: undefined }), false);
  assert.equal(answers.commits({ commits: [{ sha: "abc", message: "Fix", repo: "shell", date: "2026-10-14" }] }), true);
  assert.equal(answers.commits({ commits: [{}] }), false);
});
