import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { systemLogic, systemService } from "./fixtures/system-service.mjs";

// Count real aggregations while synthetic process I/O delivers each completed sample.
test("16 threads produce one aggregate for each completed frequency sample", () => {
  const source = fs.readFileSync(new URL("../services/SystemStats.qml", import.meta.url), "utf8");
  const finished = /id: frequencyReader[\s\S]*?waitForEnd: true\s+onStreamFinished: ([^\n]+)/.exec(source);
  assert.ok(finished, "Frequency output must be collected until the process ends");
  const readings = systemLogic("SystemReadings");
  const aggregates = [];
  const process = { running: false };
  const stats = systemService("SystemStats", { active: true, cpuGhz: null,
    frequencyReader: process, routeFile: { reload() {} }, networkFile: { reload() {} },
    cpuTempPath: "", igpuTempPath: "", fanPath: "",
    Readings: { readFrequency(values) {
      const value = readings.readFrequency(values);
      aggregates.push(value);
      return value;
    } } });
  for (let sample = 0; sample < 3; sample++) {
    stats.reloadFast();
    assert.equal(process.running, true);
    const values = [];
    for (let thread = 0; thread < 16; thread++) {
      values.push(thread < 8 ? "2000000" : "4000000");
      assert.equal(aggregates.length, sample);
    }
    stats.text = values.join("\n");
    process.running = false;
    vm.runInContext(finished[1], stats);
  }
  assert.deepEqual(aggregates, [3, 3, 3]);
  assert.equal(stats.cpuGhz, 3);
  stats.active = false;
  stats.text = "9000000\n";
  vm.runInContext(finished[1], stats);
  assert.deepEqual(aggregates, [3, 3, 3]);
  assert.equal(stats.cpuGhz, 3);
});
