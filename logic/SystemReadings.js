.pragma library

// Positions in Linux snapshots and the tab-separated hardware probe output.
var CPU_FIELDS = { name: 0, user: 1, idle: 4, ioWait: 5, steal: 8 };
var ROUTE_FIELDS = { name: 0, destination: 1 };
var NETWORK_FIELDS = { receivedBytes: 0, sentBytes: 8 };
var SENSOR_FIELDS = { kind: 0, name: 1, path: 2, label: 3 };
var DISCRETE_GPU_FIELDS = { path: 1 };
var SENSOR_KINDS = { input: "S", discreteGpu: "D" };
var PROBE_PREFIX = { distribution: "O ", kernel: "K ", hostname: "N " };
// /proc/PID/stat after the parenthesized command name. State is Linux field 3.
var PROCESS_FIELDS = { state: 0, userTicks: 11, systemTicks: 12, startedTicks: 19 };
var DISK_FIELDS = { device: 0, totalKb: 1, usedKb: 2, mount: 5 };

/** Parse one /proc/stat snapshot. Guest time is already included in user time. */
function cpuCounters(text) {
    var lines = text.split("\n");
    var counters = [];
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].trim().split(/\s+/);
        if (!/^cpu\d*$/.test(fields[CPU_FIELDS.name])) continue;
        if (fields.length <= CPU_FIELDS.idle) return null;
        var total = 0;
        for (var j = CPU_FIELDS.user; j <= Math.min(CPU_FIELDS.steal, fields.length - 1); j++) {
            var value = Number(fields[j]);
            if (!isFinite(value) || value < 0) return null;
            total += value;
        }
        counters.push({ id: fields[CPU_FIELDS.name], total: total, idle: Number(fields[CPU_FIELDS.idle]) + (Number(fields[CPU_FIELDS.ioWait]) || 0) });
    }
    return counters.length > 0 && lines[0].trim().indexOf("cpu ") === 0 ? counters : null;
}

/** Compare two counters for the same online CPU. */
function cpuPercent(now, before) {
    if (!before || now.id !== before.id) return null;
    var total = now.total - before.total;
    var idle = now.idle - before.idle;
    return total > 0 && idle >= 0 ? Math.max(0, Math.min(100, 100 * (total - idle) / total)) : null;
}

/** Group CPU numbers by the package and core IDs reported by Linux. */
function readCoreGroups(text) {
    var groups = Object.create(null);
    var lines = text.trim().split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = /^(\d+) (-?\d+) (\d+)$/.exec(lines[i].trim());
        if (!fields) continue;
        var key = fields[2] + ":" + fields[3];
        if (!groups[key]) groups[key] = [];
        groups[key].push(Number(fields[1]));
    }
    return Object.keys(groups).sort(function (a, b) {
        var first = a.split(":"), second = b.split(":");
        return Number(first[0]) - Number(second[0]) || Number(first[1]) - Number(second[1]);
    }).map(function (key) { return groups[key]; });
}

/** Return total load and one meter per detected core, or per thread without topology. */
function readCpuLoad(text, previous, groups) {
    var counters = cpuCounters(text);
    if (!counters) return null;
    var threads = counters.length - 1;
    var result = { counters: counters, threadCount: threads, percent: null, coreLoads: [] };
    if (previous && previous.length === counters.length)
        result.percent = cpuPercent(counters[0], previous[0]);
    var loads = Object.create(null);
    var beforeByCpu = Object.create(null);
    if (previous) previous.forEach(function (item) { beforeByCpu[item.id] = item; });
    for (var i = 1; i < counters.length; i++) {
        loads[Number(counters[i].id.slice(3))] = cpuPercent(counters[i], beforeByCpu[counters[i].id]) || 0;
    }
    var cores = groups && groups.length ? groups : Object.keys(loads).map(function (id) { return [Number(id)]; });
    var covered = Object.create(null);
    for (var j = 0; j < cores.length; j++) {
        var sum = 0, count = 0;
        for (var k = 0; k < cores[j].length; k++) {
            var id = cores[j][k];
            if (loads[id] === undefined) continue;
            covered[id] = true;
            sum += loads[id];
            count++;
        }
        if (count) result.coreLoads.push(sum / count);
    }
    Object.keys(loads).forEach(function (id) {
        if (!covered[id]) result.coreLoads.push(loads[id]);
    });
    return result;
}

/** Read the default route, then the matching receive and send byte counts. */
function readNetwork(routeText, deviceText) {
    var route = routeText.split("\n");
    var name = "";
    for (var i = 1; i < route.length; i++) {
        var fields = route[i].trim().split(/\s+/);
        if (fields[ROUTE_FIELDS.destination] === "00000000") { name = fields[ROUTE_FIELDS.name]; break; }
    }
    var devices = deviceText.split("\n");
    var fallback = null;
    for (var j = 2; j < devices.length; j++) {
        var colon = devices[j].indexOf(":");
        if (colon < 0) continue;
        var deviceName = devices[j].slice(0, colon).trim();
        if (deviceName === "lo") continue;
        var bytes = devices[j].slice(colon + 1).trim().split(/\s+/);
        var rx = Number(bytes[NETWORK_FIELDS.receivedBytes]), tx = Number(bytes[NETWORK_FIELDS.sentBytes]);
        if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) continue;
        var device = { name: deviceName, rx: rx, tx: tx };
        if (deviceName === name) return device;
        if (!fallback) fallback = device;
    }
    return fallback || { name: name, rx: -1, tx: -1 };
}

/** Select CPU, GPU and fan inputs from readable hwmon files. */
function readSensors(text) {
    var result = { cpuTempPath: "", igpuTempPath: "", fanPath: "", dgpuPath: "", missing: [] };
    var cpuRank = 0, fanRank = 0;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split("\t");
        if (fields[SENSOR_FIELDS.kind] === SENSOR_KINDS.discreteGpu) { result.dgpuPath = fields[DISCRETE_GPU_FIELDS.path]; continue; }
        if (fields[SENSOR_FIELDS.kind] !== SENSOR_KINDS.input || fields.length <= SENSOR_FIELDS.label) continue;
        var name = fields[SENSOR_FIELDS.name], path = fields[SENSOR_FIELDS.path], label = fields[SENSOR_FIELDS.label];
        if (/\/temp\d+_input$/.test(path)) {
            var rank = /^(CPU|Package|Tctl|Tdie)/i.test(label) ? 2
                : /^(k10temp|coretemp|zenpower)$/.test(name) ? 1 : 0;
            if (rank > cpuRank) { result.cpuTempPath = path; cpuRank = rank; }
            if (!result.igpuTempPath && /^(amdgpu|nouveau|i915)$/.test(name)) result.igpuTempPath = path;
        } else if (/\/fan\d+_input$/.test(path)) {
            var fan = name === "asus" ? 2 : 1;
            if (/CPU/i.test(label)) fan++;
            if (fan > fanRank) { result.fanPath = path; fanRank = fan; }
        }
    }
    if (!result.cpuTempPath) result.missing.push("CPU temperature");
    if (!result.igpuTempPath && !result.dgpuPath) result.missing.push("GPU temperature");
    if (!result.fanPath) result.missing.push("fan speed");
    return result;
}

/** Parse a numeric sensor reading, keeping missing readings distinct from zero. */
function readSensor(text, divisor) {
    var value = Number(text.trim());
    return text.trim() !== "" && isFinite(value) ? value / divisor : null;
}

/** Average a complete set of available CPU frequencies in kHz. */
function readFrequency(values) {
    var sum = 0, count = 0;
    for (var i = 0; i < values.length; i++) {
        var value = readSensor(values[i], 1000000);
        if (value === null || value <= 0) continue;
        sum += value;
        count++;
    }
    return count > 0 ? sum / count : null;
}

/** Read elapsed seconds from /proc/uptime. */
function readUptime(text) {
    if (text.trim() === "") return null;
    var value = Number(text.trim().split(/\s+/)[0]);
    return isFinite(value) && value >= 0 ? value : null;
}

/** Read CPU ticks and process start time from one /proc/PID/stat line. */
function processCounters(text, pid) {
    var open = text.indexOf(" (");
    var close = text.lastIndexOf(")");
    if (open < 0 || close <= open || text.slice(0, open) !== pid) return null;
    var fields = text.slice(close + 1).trim().split(/\s+/);
    if (fields.length <= PROCESS_FIELDS.startedTicks || !/^[RSDZTtXxKWPI]$/.test(fields[PROCESS_FIELDS.state])) return null;
    var user = Number(fields[PROCESS_FIELDS.userTicks]), system = Number(fields[PROCESS_FIELDS.systemTicks]);
    var started = Number(fields[PROCESS_FIELDS.startedTicks]);
    if (!isFinite(user) || !isFinite(system) || !isFinite(started)
            || user < 0 || system < 0 || started < 0) return null;
    return { ticks: user + system, started: started };
}

/** Compare /proc CPU ticks for each process found by ps. */
function readProcesses(text, previous) {
    var lines = text.split("\n");
    var totals = cpuCounters(lines[0]);
    if (!totals) return { sample: null, rows: [] };
    var current = { total: totals[0].total, processes: Object.create(null) };
    var combined = Object.create(null);
    var elapsed = previous ? current.total - previous.total : 0;
    for (var i = 1; i < lines.length; i++) {
        var fields = /^(\d+)\t([^\t]+)\t([^\t]+)\t(.+)$/.exec(lines[i]);
        if (!fields) continue;
        var pid = fields[1], mem = Number(fields[2]);
        var name = fields[3], counters = processCounters(fields[4], pid);
        if (!counters || !isFinite(mem) || mem < 0) continue;
        current.processes[pid] = { name: name, ticks: counters.ticks, started: counters.started };
        var before = previous && previous.processes[pid];
        var row = combined[name] || { name: name, cpu: 0, mem: 0 };
        if (before && before.name === name && before.started === counters.started
                && elapsed > 0 && counters.ticks >= before.ticks)
            row.cpu += 100 * (counters.ticks - before.ticks) / elapsed;
        row.mem += mem;
        combined[name] = row;
    }
    return { sample: current, rows: Object.keys(combined).map(function (name) { return combined[name]; })
        .sort(function (a, b) { return b.cpu - a.cpu || b.mem - a.mem; }).slice(0, 8) };
}

/** Read distinct disks from df, deriving percent from the same bytes as the captions. */
function readDisks(text) {
    var lines = text.trim().split("\n");
    var seen = Object.create(null);
    var found = [];
    for (var i = 1; i < lines.length; i++) {
        var fields = lines[i].trim().split(/\s+/);
        if (fields.length <= DISK_FIELDS.mount) continue;
        var total = Number(fields[DISK_FIELDS.totalKb]) / 1048576;
        var used = Number(fields[DISK_FIELDS.usedKb]) / 1048576;
        if (!isFinite(total) || !isFinite(used) || total <= 0 || used < 0 || used > total) continue;
        if (seen[fields[DISK_FIELDS.device]] !== undefined) {
            if (fields[DISK_FIELDS.mount] === "/") found[seen[fields[DISK_FIELDS.device]]].mount = "/";
            continue;
        }
        seen[fields[DISK_FIELDS.device]] = found.length;
        found.push({ mount: fields[DISK_FIELDS.mount], device: fields[DISK_FIELDS.device].split("/").pop(),
            usedGb: used, totalGb: total, percent: 100 * used / total });
    }
    return found.sort(function (a, b) { return (a.mount === "/" ? -1 : 0) - (b.mount === "/" ? -1 : 0); });
}
