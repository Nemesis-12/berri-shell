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

function procLine(pid, name, user, system, started) {
  const fields = Array(23).fill("0");
  fields[1] = String(pid);
  fields[2] = `(${name})`;
  fields[3] = "S";
  fields[14] = String(user);
  fields[15] = String(system);
  fields[22] = String(started);
  return fields.slice(1).join(" ");
}

test("process rows use CPU ticks from the last sample and sort by them", () => {
  const first = "cpu 100 0 0 900\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 100, 0, 1000)}\n`
    + `102\t2.0\tfirefox\t${procLine(102, "firefox", 50, 0, 1000)}\n`
    + `201\t0.5\tcode\t${procLine(201, "code", 20, 0, 1000)}\n`
    + `301\t0.2\tbackup\t${procLine(301, "backup", 0, 0, 1000)}\n`;
  const second = "cpu 500 0 0 1500\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 200, 0, 1000)}\n`
    + `102\t2.0\tfirefox\t${procLine(102, "firefox", 150, 0, 1000)}\n`
    + `201\t0.5\tcode\t${procLine(201, "code", 320, 0, 1000)}\n`
    + `301\t0.2\tbackup\t${procLine(301, "backup", 5, 0, 1000)}\n`;
  const before = readings.readProcesses(first, null);
  assert.deepEqual(Array.from(before.rows), []);
  const after = readings.readProcesses(second, before.sample);
  assert.deepEqual(Array.from(after.rows, row => [row.name, row.cpu, row.mem]),
    [["code", 30, 0.5], ["firefox", 20, 3], ["backup", 0.5, 0.2]]);
});

test("process rows ignore new and restarted PIDs until the next sample", () => {
  const first = "cpu 100 0 0 900\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 100, 0, 1000)}\n`;
  const second = "cpu 500 0 0 1500\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 200, 0, 2000)}\n`
    + `202\t2.0\tcode\t${procLine(202, "code", 300, 0, 1500)}\n`;
  const before = readings.readProcesses(first, null);
  const after = readings.readProcesses(second, before.sample);
  assert.deepEqual(Array.from(after.rows, row => [row.name, row.cpu]), []);
});

test("disk rows keep two large unique devices", () => {
  const data = "Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "/dev/nvme0n1p2 104857600 52428800 52428800 50% /\n"
    + "/dev/nvme0n1p2 104857600 52428800 52428800 50% /home\n"
    + "tmpfs 1024 512 512 50% /run\n"
    + "/dev/sda1 41943040 10485760 31457280 25% /data\n"
    + "/dev/sdb1 31457280 1048576 30408704 3% /extra\n";
  assert.deepEqual(Array.from(readings.readDisks(data), row => [row.mount, row.device, row.usedGb, row.totalGb]),
    [["/", "nvme0n1p2", 50, 100], ["/data", "sda1", 10, 40]]);
});

test("the first process sample shows memory rows before CPU deltas exist", () => {
  const sample = "cpu 100 0 0 900\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 100, 0, 1000)}\n`
    + `102\t2.0\tfirefox\t${procLine(102, "firefox", 50, 0, 1000)}\n`
    + `201\t0.5\tcode\t${procLine(201, "code", 20, 0, 1000)}\n`;
  const result = readings.readProcesses(sample, null);
  assert.deepEqual(Array.from(result.rows, row => [row.name, row.cpu, row.mem]),
    [["firefox", 0, 3], ["code", 0, 0.5]]);
});
