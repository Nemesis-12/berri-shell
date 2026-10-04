import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { execFileSync } from "node:child_process";
import { systemService, systemLogic } from "./fixtures/system-service.mjs";

// Sensor I/O and logs are the boundary; the service owns missing-value state.
test("missing sensors log once across reopen and failed reads", () => {
  const warnings = [];
  const stats = systemService("SystemStats", { sensorWarnings: {},
    cpuTempC: null, igpuTempC: null, gpuTempC: null, dgpuTempC: null, fanRpm: null,
    console: { warn(message) { warnings.push(message); } } });
  stats.readProbe("");
  stats.readProbe("");
  stats.readSensorSample("CPU temperature", "", 1000);
  stats.readSensorSample("GPU temperature", "", 1000);
  stats.readSensorSample("fan speed", "", 1);
  assert.deepEqual(warnings, ["SystemStats: CPU temperature sensor is unavailable",
    "SystemStats: GPU temperature sensor is unavailable", "SystemStats: fan speed sensor is unavailable"]);
  assert.deepEqual([stats.cpuTempC, stats.gpuTempC, stats.fanRpm], [null, null, null]);
  stats.readSensorSample("CPU temperature", "54000", 1000);
  stats.readSensorSample("fan speed", "0", 1);
  assert.deepEqual([stats.cpuTempC, stats.fanRpm], [54, 0]);
  stats.readSensorSample("CPU temperature", "bad", 1000);
  assert.equal(stats.cpuTempC, null);
  assert.equal(warnings.length, 3);
});

test("the actual process command supplies rows within the opening deadline", () => {
  const source = fs.readFileSync(new URL("../services/SystemStats.qml", import.meta.url), "utf8");
  const command = /id: processReader\s+command: (\[[\s\S]*?\])\s+stdout:/.exec(source);
  assert.ok(command, "The process sample command must exist");
  const [program, ...args] = vm.runInNewContext(command[1]);
  const sample = execFileSync(program, args, { encoding: "utf8", timeout: 2500 });
  const result = systemLogic("SystemReadings").readProcesses(sample, null);
  assert.ok(result.rows.length >= 1, "A completed first sample must show a row");
  assert.match(result.rows[0].name, /\S/);
  assert.equal(result.rows[0].cpu, 0);
});

test("shared usage publishes disk, memory, and uptime from completed samples", () => {
  const usage = systemService("SystemUsage", { memory: null, disks: [], uptimeSeconds: 0 });
  usage.readDisk("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "/dev/root 104857600 52428800 10485760 84% /\n");
  usage.readMemory("MemTotal: 8388608 kB\nMemAvailable: 2097152 kB\nSwapTotal: 1048576 kB\nSwapFree: 524288 kB\n");
  usage.readUptime("15120 9900\n");
  assert.deepEqual(Array.from(usage.disks, disk => [disk.usedGb, disk.totalGb, disk.percent]), [[50, 100, 50]]);
  assert.deepEqual([usage.memory.usedGb, usage.memory.totalGb, usage.memory.percent,
    usage.memory.swapUsedGb, usage.uptimeSeconds], [6, 8, 75, 0.5, 15120]);
});

test("core topology preserves the total load signal used by automatic power mode", () => {
  const measured = [];
  const load = systemService("CpuLoad", { previousCounters: null, coreGroups: [], percent: 0,
    measured(percent) { measured.push(percent); } });
  load.readSample("cpu 100 0 100 800\ncpu0 50 0 50 400\ncpu1 50 0 50 400");
  load.coreGroups = systemLogic("SystemReadings").readCoreGroups("0 0 0\n1 0 0\n");
  load.readSample("cpu 150 0 150 900\ncpu0 75 0 75 450\ncpu1 75 0 75 450");
  load.readSample("cpu 150 0 150 900\ncpu0 75 0 75 450\ncpu1 75 0 75 450");
  assert.deepEqual(measured, [50]);
  assert.equal(load.percent, 50);
  assert.equal(load.threadCount, 2);
});
