import { test } from "node:test";
import assert from "node:assert/strict";
import { systemLogic } from "./fixtures/system-service.mjs";

const readings = systemLogic("SystemReadings");

// One known stat line fixes the field positions independently of the parser's definitions.
test("a shifted process state returns no reading while the valid line keeps its CPU ticks", () => {
  const stat = "101 (worker (helper)) S 1 2 3 4 5 6 7 8 9 10 120 30 0 0 20 0 1 0 700";
  const valid = readings.processCounters(stat, "101");
  assert.deepEqual([valid.ticks, valid.started], [150, 700]);
  const shifted = stat.replace(") S ", ") 0 S ");
  assert.equal(readings.processCounters(shifted, "101"), null);
  const prefix = "cpu 100 0 0 900\n101\t1.5\tworker\t";
  assert.deepEqual(Array.from(readings.readProcesses(prefix + shifted, null).rows), []);
  assert.deepEqual(Array.from(readings.readProcesses(prefix + stat, null).rows, row => [row.name, row.cpu, row.mem]),
    [["worker", 0, 1.5]]);
});
