import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../logic/SystemReadings.js", import.meta.url), "utf8")
  .replace(/^\.pragma library.*$/m, "");
const readings = vm.createContext({});
vm.runInContext(source, readings);

test("one CPU sample supplies total and per-thread load without topology", () => {
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
  const groups = readings.readCoreGroups(Array.from({ length: 16 }, (_, i) => `${i} 0 ${i % 8}`).join("\n"));
  const first = readings.readCpuLoad(before, null, groups);
  const next = readings.readCpuLoad(after, first.counters, groups);
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
  assert.deepEqual(Array.from(before.rows, row => [row.name, row.cpu, row.mem]),
    [["firefox", 0, 3], ["code", 0, 0.5], ["backup", 0, 0.2]]);
  const after = readings.readProcesses(second, before.sample);
  assert.deepEqual(Array.from(after.rows, row => [row.name, row.cpu, row.mem]),
    [["code", 30, 0.5], ["firefox", 20, 3], ["backup", 0.5, 0.2]]);
});

test("new and restarted PIDs show memory without a false CPU delta", () => {
  const first = "cpu 100 0 0 900\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 100, 0, 1000)}\n`;
  const second = "cpu 500 0 0 1500\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 200, 0, 2000)}\n`
    + `202\t2.0\tcode\t${procLine(202, "code", 300, 0, 1500)}\n`;
  const before = readings.readProcesses(first, null);
  const after = readings.readProcesses(second, before.sample);
  assert.deepEqual(Array.from(after.rows, row => [row.name, row.cpu, row.mem]),
    [["code", 0, 2], ["firefox", 0, 1]]);
});

test("disk parsing keeps distinct devices without a fixed size or count", () => {
  const data = "Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "/dev/nvme0n1p2 104857600 52428800 52428800 50% /\n"
    + "/dev/nvme0n1p2 104857600 52428800 52428800 50% /home\n"
    + "/dev/sda1 41943040 10485760 31457280 25% /data\n"
    + "/dev/sdb1 31457280 1048576 30408704 3% /extra\n";
  assert.deepEqual(Array.from(readings.readDisks(data), row => [row.mount, row.device, row.usedGb, row.totalGb]),
    [["/", "nvme0n1p2", 50, 100], ["/data", "sda1", 10, 40], ["/extra", "sdb1", 1, 30]]);
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

test("core topology supports six SMT cores and sparse CPU numbers", () => {
  const topology = readings.readCoreGroups("0 0 0\n2 0 0\n4 0 1\n6 0 1\n8 0 2\n10 0 2\n"
    + "12 1 0\n14 1 0\n16 1 1\n18 1 1\n20 1 2\n22 1 2\n");
  const before = "cpu 0 0 0 1200\n" + [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]
    .map(id => `cpu${id} 0 0 0 100`).join("\n");
  const after = "cpu 600 0 0 1800\n" + [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]
    .map(id => `cpu${id} ${id === 2 ? 100 : 0} 0 0 ${id === 2 ? 100 : 200}`).join("\n");
  const first = readings.readCpuLoad(before, null, topology);
  assert.deepEqual(Array.from(first.coreLoads), [0, 0, 0, 0, 0, 0]);
  assert.deepEqual(Array.from(readings.readCpuLoad(after, first.counters, topology).coreLoads),
    [50, 0, 0, 0, 0, 0]);
});

test("sensor detection uses readable inputs and reports each missing sensor", () => {
  const paths = readings.readSensors("S\tcoretemp\t/sys/hwmon0/temp1_input\tPackage id 0\n"
    + "S\tother\t/sys/hwmon1/fan2_input\tCPU Fan\n");
  assert.equal(paths.cpuTempPath, "/sys/hwmon0/temp1_input");
  assert.equal(paths.fanPath, "/sys/hwmon1/fan2_input");
  assert.deepEqual(Array.from(paths.missing), ["GPU temperature"]);
  assert.deepEqual(Array.from(readings.readSensors("").missing),
    ["CPU temperature", "GPU temperature", "fan speed"]);
  assert.equal(readings.readSensors("S\tk10temp\t/sys/amd/temp1_input\tTctl\n"
    + "S\tamdgpu\t/sys/gpu/temp1_input\tedge\n"
    + "S\tasus\t/sys/asus/fan1_input\t\n").igpuTempPath, "/sys/gpu/temp1_input");
});

test("one disk parser derives ring percent from the bytes shown in text", () => {
  const result = readings.readDisks("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "/dev/root 10485760 5242880 1048576 84% /\n");
  assert.deepEqual(Array.from(result, disk => [disk.mount, disk.usedGb, disk.totalGb, disk.percent]),
    [["/", 5, 10, 50]]);
});

test("sensor text keeps an unavailable reading separate from a stopped fan", () => {
  const format = vm.createContext({});
  vm.runInContext(fs.readFileSync(new URL("../logic/SystemFormat.js", import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, ""), format);
  assert.equal(format.sensor(null, "°C", 0), "-");
  assert.equal(format.sensor(0, "", 0), "0");
  assert.equal(format.sensor(2.345, " GHZ", 2), "2.35 GHZ");
});

test("core meters are not capped at eight and offline siblings are excluded", () => {
  const groups = readings.readCoreGroups(Array.from({ length: 12 }, (_, i) => `${i} 0 ${i}`).join("\n"));
  const sample = "cpu 0 0 0 1200\n" + Array.from({ length: 12 }, (_, i) => `cpu${i} 0 0 0 100`).join("\n");
  assert.deepEqual(Array.from(readings.readCpuLoad(sample, null, groups).coreLoads),
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  const paired = readings.readCoreGroups("0 0 0\n1 0 0\n2 0 1\n3 0 1\n");
  const before = readings.readCpuLoad("cpu 0 0 0 200\ncpu0 0 0 0 100\ncpu2 0 0 0 100", null, paired);
  const after = readings.readCpuLoad("cpu 100 0 0 300\ncpu0 100 0 0 100\ncpu2 0 0 0 200", before.counters, paired);
  assert.deepEqual(Array.from(after.coreLoads), [100, 0]);
});

test("root disk remains available when df lists another mount of it first", () => {
  const disks = readings.readDisks("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "/dev/shared 104857600 52428800 10485760 84% /home\n"
    + "/dev/shared 104857600 52428800 10485760 84% /\n");
  assert.deepEqual(Array.from(disks, disk => [disk.mount, disk.percent]), [["/", 50]]);
});

test("sensor detection prefers CPU package temperature and the ASUS CPU fan", () => {
  const sensors = readings.readSensors("S\tcoretemp\t/sys/cpu/temp10_input\tCore 8\n"
    + "S\tcoretemp\t/sys/cpu/temp1_input\tPackage id 0\n"
    + "S\tasus\t/sys/asus/fan1_input\tCPU Fan\n"
    + "S\tasus\t/sys/asus/fan2_input\tGPU Fan\n");
  assert.equal(sensors.cpuTempPath, "/sys/cpu/temp1_input");
  assert.equal(sensors.fanPath, "/sys/asus/fan1_input");
});

test("core topology orders packages and core IDs rather than directory names", () => {
  const groups = readings.readCoreGroups("10 0 5\n2 0 1\n0 0 0\n20 1 0\n");
  assert.deepEqual(Array.from(groups, group => Array.from(group)), [[0], [2], [10], [20]]);
});

test("a changed online thread count starts a fresh total load interval", () => {
  const first = readings.readCpuLoad("cpu 100 0 0 900\ncpu0 100 0 0 900", null);
  const after = readings.readCpuLoad("cpu 300 0 0 1700\ncpu0 150 0 0 950\ncpu1 150 0 0 750", first.counters);
  assert.equal(after.percent, null);
  assert.equal(after.threadCount, 2);
  assert.deepEqual(Array.from(after.coreLoads), [50, 0]);
});
