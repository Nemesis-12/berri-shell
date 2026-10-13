// Runs quick-add-dates.test.mjs in several time zones. The parser works on local dates, so a zone with a day shift or DST must give the same days.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

const datesTest = new URL("./quick-add-dates.test.mjs", import.meta.url).pathname;

for (const TZ of ["UTC", "America/Los_Angeles", "Asia/Kolkata", "Pacific/Kiritimati"]) {
  test(`quick-add date phrases in ${TZ}`, () => {
    const run = spawnSync(process.execPath, ["--test", datesTest], { env: { ...process.env, TZ }, encoding: "utf8" });
    assert.equal(run.status, 0, run.stdout + run.stderr);
  });
}
