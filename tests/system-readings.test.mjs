import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/SystemReadings.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");
const readings = vm.createContext({});
vm.runInContext(source, readings);

test("one CPU sample supplies total and paired core load", () => {
  const before = ["cpu  100 0 100 800 0", "cpu0 50 0 50 400 0", "cpu1 50 0 50 400 0"].join("\n");
  const after = ["cpu  150 0 150 900 0", "cpu0 75 0 75 450 0", "cpu1 75 0 75 450 0"].join("\n");
  const first = readings.readCpuLoad(before, null);
  assert.equal(first.percent, null);
  const next = readings.readCpuLoad(after, first.counters);
  assert.equal(next.percent, 50);
  assert.deepEqual(Array.from(next.coreLoads), [50, 50]);
  assert.equal(next.threadCount, 2);
});

test("CPU load ignores invalid and unchanged counters", () => {
  assert.equal(readings.readCpuLoad("cpu bad data", null), null);
  const first = readings.readCpuLoad("cpu 1 0 1 8", null);
  assert.equal(readings.readCpuLoad("cpu 1 0 1 8", first.counters).percent, null);
});

test("paired CPU threads give one load for each physical core", () => {
  const before = ["cpu 0 0 0 1600", ...Array.from({ length: 16 }, (_, i) => `cpu${i} 0 0 0 100`)].join("\n");
  const after = ["cpu 800 0 0 2400", ...Array.from({ length: 16 }, (_, i) =>
    `cpu${i} ${i === 0 ? 100 : 0} 0 0 ${i === 0 ? 100 : 200}`)].join("\n");
  const first = readings.readCpuLoad(before, null);
  const next = readings.readCpuLoad(after, first.counters);
  assert.equal(next.coreLoads.length, 8);
  assert.equal(next.coreLoads[0], 50);
  assert.equal(next.coreLoads[1], 0);
});

test("network reads the default route and device byte counters", () => {
  const route = "Iface Destination Gateway Flags\nwlan0 00000000 01020304 0003\n";
  const devices = "Inter-| Receive | Transmit\n face |bytes |bytes\n    lo: 9 0 0 0 0 0 0 0 9 0 0 0 0 0 0 0\n wlan0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0\n";
  const result = readings.readNetwork(route, devices);
  assert.equal(result.name, "wlan0");
  assert.equal(result.rx, 1048576);
  assert.equal(result.tx, 2097152);
});

test("frequency and sensor values reject invalid input", () => {
  assert.equal(readings.readFrequency(["3000000", "2000000", "bad"]), 2.5);
  assert.equal(readings.readSensor("54000\n", 1000), 54);
  assert.equal(readings.readSensor("bad", 1000), null);
  assert.equal(readings.readUptime("1234.56 999.00\n"), 1234.56);
});

test("process rows combine names and use whole CPU share", () => {
  const data = "%CPU %MEM COMMAND\n30.0 1.0 firefox\n20.0 2.0 firefox\n10.0 0.5 code\n";
  const rows = Array.from(readings.readProcesses(data, 2));
  assert.deepEqual(rows.map(row => [row.name, row.cpu, row.mem]),
    [["firefox", 25, 3], ["code", 5, 0.5]]);
});
