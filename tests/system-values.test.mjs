import { test } from "node:test";
import assert from "node:assert/strict";
import { systemLogic, systemService } from "./fixtures/system-service.mjs";

// Value rules of the System tab: loading, units, disk names and network rates.
const readings = systemLogic("SystemReadings");
const format = systemLogic("SystemFormat");

function procLine(pid, name, user, started) {
  const fields = Array(23).fill("0");
  fields[1] = String(pid);
  fields[2] = `(${name})`;
  fields[3] = "S";
  fields[14] = String(user);
  fields[22] = String(started);
  return fields.slice(1).join(" ");
}

test("the first CPU sample has no total, core or process load", () => {
  const first = readings.readCpuLoad("cpu 100 0 100 800\ncpu0 50 0 50 400\ncpu1 50 0 50 400", null);
  assert.equal(first.percent, null);
  assert.deepEqual(Array.from(first.coreLoads), [null, null]);
  const text = "cpu 100 0 0 900\n" + `101\t1.0\tfirefox\t${procLine(101, "firefox", 100, 1000)}\n`;
  assert.equal(readings.readProcesses(text, null).rows[0].cpu, null);
});

test("a second CPU sample gives numbers, and a new process starts at zero", () => {
  const first = readings.readProcesses("cpu 100 0 0 900\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 100, 1000)}\n`, null);
  const next = readings.readProcesses("cpu 500 0 0 1500\n"
    + `101\t1.0\tfirefox\t${procLine(101, "firefox", 200, 1000)}\n`
    + `202\t2.0\tcode\t${procLine(202, "code", 300, 1500)}\n`, first.sample);
  assert.deepEqual(Array.from(next.rows, row => [row.name, row.cpu]), [["firefox", 10], ["code", 0]]);
});

test("loading CPU readings show a dash and measured ones show numbers", () => {
  assert.equal(format.wholePercent(null), "-");
  assert.equal(format.wholePercent(0), "0");
  assert.equal(format.wholePercent(41.6), "42");
  assert.equal(format.processCpu(null), "-");
  assert.equal(format.processCpu(0), "0.0%");
  assert.equal(format.processCpu(0.01), "<0.05%");
  assert.equal(format.processCpu(12.34), "12.3%");
});

test("network rates are zero without a comparable pair of samples", () => {
  const before = { name: "wlan0", rx: 0, tx: 0, time: 1000 };
  const rates = readings.networkRates(before, { name: "wlan0", rx: 2097152, tx: 1048576 }, 2000);
  assert.deepEqual([rates.down, rates.up], [2, 1]);
  const none = { name: "", rx: -1, tx: -1 };
  assert.deepEqual(Object.values(readings.networkRates(before, none, 2000)), [0, 0]);
  assert.deepEqual(Object.values(readings.networkRates(null, before, 2000)), [0, 0]);
  const moved = { name: "eth0", rx: 9e9, tx: 9e9 };
  assert.deepEqual(Object.values(readings.networkRates(before, moved, 2000)), [0, 0]);
  const backwards = { name: "wlan0", rx: 0, tx: 0 };
  assert.deepEqual(Object.values(readings.networkRates({ ...before, rx: 5, tx: 5 }, backwards, 2000)), [0, 0]);
});

test("binary quantities carry binary unit labels", () => {
  assert.equal(format.usedOfTotal(148.4, 512), "148 / 512 GiB");
  assert.equal(format.usedOfTotal(1228.8, 2048), "1.2 / 2 TiB");
  assert.equal(format.usedOfTotal(500, 1000), "500 / 1000 GiB");
  assert.equal(format.rate(1.234), "1.2");
  assert.equal(format.rateUnit, "MiB/S");
  assert.equal(format.memoryTotal(15.6), "/ 16 GiB");
});

test("a disk mount path with spaces is read whole", () => {
  const disks = readings.readDisks("Filesystem 1024-blocks Used Available Capacity Mounted on\n"
    + "/dev/sda1 41943040 10485760 31457280 25% /mnt/Drive D\n"
    + "/dev/sdb1 31457280 1048576 30408704 3% /media/a  b\n");
  assert.deepEqual(Array.from(disks, disk => [disk.mount, disk.device, disk.usedGb, disk.totalGb]),
    [["/mnt/Drive D", "sda1", 10, 40], ["/media/a  b", "sdb1", 1, 30]]);
});

test("the CPU service is not ready until it has two samples, and again after a pause", () => {
  const load = systemService("CpuLoad", { previousCounters: null, coreGroups: [], percent: 0, ready: false,
    coreLoads: [], threadCount: 0, measured() {} });
  load.readSample("cpu 100 0 100 800\ncpu0 50 0 50 400\ncpu1 50 0 50 400");
  assert.equal(load.ready, false);
  assert.deepEqual(Array.from(load.coreLoads), [null, null]);
  load.readSample("cpu 150 0 150 900\ncpu0 75 0 75 450\ncpu1 75 0 75 450");
  assert.equal(load.ready, true);
  assert.equal(load.percent, 50);
});

test("network rates fall to zero when the route disappears and after a reopen", () => {
  const stats = systemService("SystemStats", { prevNet: null, netName: "", downMiBs: 0, upMiBs: 0,
    routeFile: { text: () => "Iface Destination\nwlan0 00000000\n" },
    networkFile: { text: () => "h\nh\n wlan0: 1048576 0 0 0 0 0 0 0 1048576 0 0 0 0 0 0 0\n" } });
  stats.readNetwork();
  assert.deepEqual([stats.downMiBs, stats.upMiBs], [0, 0]);
  stats.prevNet.time -= 1000;
  stats.networkFile = { text: () => "h\nh\n wlan0: 3145728 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0\n" };
  stats.readNetwork();
  assert.ok(Math.abs(stats.downMiBs - 2) < 0.1 && Math.abs(stats.upMiBs - 1) < 0.1, `${stats.downMiBs} ${stats.upMiBs}`);
  stats.routeFile = { text: () => "Iface Destination\n" };
  stats.networkFile = { text: () => "h\nh\n" };
  stats.readNetwork();
  assert.deepEqual([stats.downMiBs, stats.upMiBs, stats.netName, stats.prevNet], [0, 0, "", null]);
});

test("the process sampler stays fast until a CPU number exists", () => {
  const stats = systemService("SystemStats", { prevProcessSample: null, processes: [], processCpuKnown: false });
  const line = (ticks) => `101\t1.0\tfirefox\t${procLine(101, "firefox", ticks, 1000)}\n`;
  stats.readProcessSample("cpu 100 0 0 900\n" + line(100));
  assert.equal(stats.processCpuKnown, false);
  stats.readProcessSample("cpu 500 0 0 1500\n" + line(200));
  assert.equal(stats.processCpuKnown, true);
});

test("the process service keeps null CPU for the first sample and numbers after", () => {
  const stats = systemService("SystemStats", { prevProcessSample: null, processes: [] });
  const line = (ticks) => `101\t1.0\tfirefox\t${procLine(101, "firefox", ticks, 1000)}\n`;
  stats.readProcessSample("cpu 100 0 0 900\n" + line(100));
  assert.equal(stats.processes[0].cpu, null);
  stats.readProcessSample("cpu 500 0 0 1500\n" + line(200));
  assert.equal(stats.processes[0].cpu, 100 * 100 / 1000);
});

test("a thread whose counters did not advance stays unknown and is left out of the core average", () => {
  const before = "cpu 0 0 0 200\ncpu0 0 0 0 100\ncpu1 0 0 0 100";
  const after = "cpu 100 0 0 300\ncpu0 100 0 0 100\ncpu1 0 0 0 100";
  const first = readings.readCpuLoad(before, null);
  assert.deepEqual(Array.from(readings.readCpuLoad(after, first.counters).coreLoads), [100, null]);
  const groups = readings.readCoreGroups("0 0 0\n1 0 0");
  assert.deepEqual(Array.from(readings.readCpuLoad(after, first.counters, groups).coreLoads), [100]);
});
