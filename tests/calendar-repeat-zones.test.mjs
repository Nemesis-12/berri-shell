import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// Each child loads the real calendar modules with its display zone set at startup.
for (const zone of ["America/Chicago", "Pacific/Auckland", "Asia/Tokyo", "UTC"]) {
  test(`repeat rules keep an edited local UNTIL day in ${zone}`, () => {
    const env = { ...process.env, TZ: zone };
    // The child needs its own test runner, rather than the parent's IPC context.
    delete env.NODE_TEST_CONTEXT;
    const result = spawnSync(process.execPath,
      ["--test", "--test-reporter=tap", fileURLToPath(new URL("./fixtures/calendar-repeat-zone-check.mjs", import.meta.url))],
      { env, encoding: "utf8", timeout: 180000 });
    assert.equal(result.status, 0, result.error?.message || `${result.stdout}${result.stderr}`);
    assert.match(result.stdout, /# tests 5\n/);
  });
}
