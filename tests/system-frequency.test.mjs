import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

// Run service functions and completion handlers with synthetic file/process I/O.
function frequencyService() {
  const source = fs.readFileSync(new URL("../services/SystemStats.qml", import.meta.url), "utf8");
  const logic = fs.readFileSync(new URL("../logic/SystemReadings.js", import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, "");
  const readings = vm.createContext({});
  vm.runInContext(logic, readings);
  const aggregates = [];
  const values = Array(16).fill("");
  const service = vm.createContext({
    active: true, cpuGhz: null,
    Readings: { readFrequency(samples) {
      const value = readings.readFrequency(samples);
      aggregates.push(value);
      return value;
    } },
    frequencyFiles: { count: 16, objectAt(index) { return { text: () => values[index] }; } },
  });
  service.root = service;
  for (const [, name, args, body] of source.matchAll(/^    function (\w+)\((.*?)\) \{([\s\S]*?)^    \}/gm))
    vm.runInContext(`function ${name}(${args}) {${body}\n}`, service);
  const perFile = /id: frequencyFiles[\s\S]*?onLoaded: ([^\n]+)/.exec(source);
  const complete = /id: frequencyReader[\s\S]*?waitForEnd: true\s+onStreamFinished: ([^\n]+)/.exec(source);
  assert.ok(perFile || complete, "A frequency completion handler must exist");
  return { service, aggregates, tick() {
    for (let thread = 0; thread < 16; thread++) {
      values[thread] = thread < 8 ? "2000000" : "4000000";
      if (perFile) vm.runInContext(perFile[1], service);
      else assert.equal(aggregates.length, this.completedTicks);
    }
    if (complete) {
      service.text = values.join("\n");
      vm.runInContext(complete[1], service);
    }
    this.completedTicks++;
  }, completedTicks: 0 };
}

test("16 threads produce one frequency aggregate per completed one-second sample", () => {
  const reader = frequencyService();
  for (let second = 0; second < 3; second++) reader.tick();
  assert.deepEqual(reader.aggregates, [3, 3, 3]);
  assert.equal(reader.service.cpuGhz, 3);
});
