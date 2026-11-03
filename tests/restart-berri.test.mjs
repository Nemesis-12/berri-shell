// restart-berri.sh starts berri in its own systemd scope and falls back to a plain start.
// Every command that could touch a real process is a stub in a temporary folder.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repo = new URL("../", import.meta.url).pathname;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Build a copy of the repo layout and a stub PATH. systemd-run runs the command after "--",
// or exits 1 without running it when STUB_SYSTEMD_RUN_FAILS is set.
const makeSandbox = () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "berri-restart-"));
  const bin = path.join(root, "bin");
  const logs = path.join(root, "logs");
  fs.mkdirSync(path.join(root, "tools"));
  fs.mkdirSync(bin);
  fs.mkdirSync(logs);
  fs.copyFileSync(path.join(repo, "tools/restart-berri.sh"), path.join(root, "tools/restart-berri.sh"));
  const stub = (dir, name, body) => fs.writeFileSync(path.join(dir, name), `#!/bin/sh\n${body}\n`, { mode: 0o755 });
  stub(path.join(root, "tools"), "start-berri.sh", 'echo started >> "$STUB_LOGS/berri"');
  stub(bin, "pgrep", "exit 1");
  stub(bin, "kill", 'echo "$*" >> "$STUB_LOGS/kill"');
  stub(bin, "setsid", 'exec "$@"');
  stub(
    bin,
    "systemd-run",
    [
      'echo "$*" >> "$STUB_LOGS/systemd-run"',
      '[ -n "$STUB_SYSTEMD_RUN_FAILS" ] && exit 1',
      'while [ "$1" != "--" ]; do shift; done',
      "shift",
      'exec "$@"',
    ].join("\n"),
  );
  return { root, bin, logs };
};

const lines = (file) => (fs.existsSync(file) ? fs.readFileSync(file, "utf8").split("\n").filter(Boolean) : []);

// Run the script, then wait for the detached start. Wait again to catch a second start.
const restart = async ({ systemdRunFails }) => {
  const { root, bin, logs } = makeSandbox();
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, STUB_LOGS: logs };
  if (systemdRunFails) env.STUB_SYSTEMD_RUN_FAILS = "1";
  else delete env.STUB_SYSTEMD_RUN_FAILS;
  const result = spawnSync("sh", [path.join(root, "tools/restart-berri.sh")], { encoding: "utf8", env });
  for (let waited = 0; waited < 3000 && lines(path.join(logs, "berri")).length === 0; waited += 50) await sleep(50);
  await sleep(300);
  return {
    result,
    root: fs.realpathSync(root),
    starts: lines(path.join(logs, "berri")),
    systemdRuns: lines(path.join(logs, "systemd-run")),
    kills: lines(path.join(logs, "kill")),
  };
};

test("berri starts once in its own user scope, so it outlives the process that started it", async () => {
  const { result, root, starts, systemdRuns, kills } = await restart({ systemdRunFails: false });
  assert.equal(result.status, 0, result.stderr);
  const launch = systemdRuns.find((line) => line.includes(`${root}/tools/start-berri.sh`));
  assert.ok(launch, systemdRuns.join("\n"));
  assert.match(launch, /^--user --scope --collect --quiet --unit=berri-shell-\d+ --slice=app\.slice -- /);
  assert.deepEqual(starts, ["started"]);
  assert.deepEqual(kills, []);
});

test("berri starts once with a plain start when systemd-run fails", async () => {
  const { result, starts, systemdRuns } = await restart({ systemdRunFails: true });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(systemdRuns.length > 0);
  assert.deepEqual(starts, ["started"]);
});
