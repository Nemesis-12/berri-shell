.pragma library

/** Parse one /proc/stat snapshot. Guest time is already included in user time. */
function cpuCounters(text) {
    var lines = text.split("\n");
    var counters = [];
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].trim().split(/\s+/);
        if (!/^cpu\d*$/.test(fields[0])) continue;
        if (fields.length < 5) return null;
        var total = 0;
        for (var j = 1; j <= Math.min(8, fields.length - 1); j++) {
            var value = Number(fields[j]);
            if (!isFinite(value) || value < 0) return null;
            total += value;
        }
        counters.push({ total: total, idle: Number(fields[4]) + (Number(fields[5]) || 0) });
    }
    return counters.length > 0 && lines[0].trim().indexOf("cpu ") === 0 ? counters : null;
}

function cpuPercent(now, before) {
    var total = now.total - before.total;
    var idle = now.idle - before.idle;
    return total > 0 && idle >= 0 ? Math.max(0, Math.min(100, 100 * (total - idle) / total)) : null;
}

/** Return the total and up to eight physical core loads from one snapshot. */
function readCpuLoad(text, previous) {
    var counters = cpuCounters(text);
    if (!counters) return null;
    var threads = counters.length - 1;
    var result = { counters: counters, threadCount: threads, percent: null, coreLoads: [] };
    if (!previous || previous.length !== counters.length) return result;
    result.percent = cpuPercent(counters[0], previous[0]);
    var paired = threads >= 16 && threads % 2 === 0;
    var cores = paired ? threads / 2 : threads;
    for (var i = 0; i < Math.min(8, cores); i++) {
        var first = cpuPercent(counters[i + 1], previous[i + 1]);
        if (first === null) { result.coreLoads.push(0); continue; }
        if (paired) {
            var second = cpuPercent(counters[i + cores + 1], previous[i + cores + 1]);
            result.coreLoads.push(second === null ? first : (first + second) / 2);
        } else result.coreLoads.push(first);
    }
    return result;
}

/** Read the default route, then the matching receive and send byte counts. */
function readNetwork(routeText, deviceText) {
    var route = routeText.split("\n");
    var name = "";
    for (var i = 1; i < route.length; i++) {
        var fields = route[i].trim().split(/\s+/);
        if (fields[1] === "00000000") { name = fields[0]; break; }
    }
    var devices = deviceText.split("\n");
    var fallback = null;
    for (var j = 2; j < devices.length; j++) {
        var colon = devices[j].indexOf(":");
        if (colon < 0) continue;
        var deviceName = devices[j].slice(0, colon).trim();
        if (deviceName === "lo") continue;
        var bytes = devices[j].slice(colon + 1).trim().split(/\s+/);
        var rx = Number(bytes[0]), tx = Number(bytes[8]);
        if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) continue;
        var device = { name: deviceName, rx: rx, tx: tx };
        if (deviceName === name) return device;
        if (!fallback) fallback = device;
    }
    return fallback || { name: name, rx: -1, tx: -1 };
}

function readSensor(text, divisor) {
    var value = Number(text.trim());
    return text.trim() !== "" && isFinite(value) ? value / divisor : null;
}

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
    if (fields.length < 20) return null;
    var user = Number(fields[11]), system = Number(fields[12]), started = Number(fields[19]);
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
        if (!before || before.name !== name || before.started !== counters.started
                || elapsed <= 0 || counters.ticks < before.ticks) continue;
        var row = combined[name] || { name: name, cpu: 0, mem: 0 };
        row.cpu += 100 * (counters.ticks - before.ticks) / elapsed;
        row.mem += mem;
        combined[name] = row;
    }
    return { sample: current, rows: Object.keys(combined).map(function (name) { return combined[name]; })
        .sort(function (a, b) { return b.cpu - a.cpu; }).slice(0, 8) };
}

/** Keep the first two large, distinct disks from df output. */
function readDisks(text) {
    var lines = text.trim().split("\n");
    var seen = Object.create(null);
    var found = [];
    for (var i = 1; i < lines.length && found.length < 2; i++) {
        var fields = lines[i].trim().split(/\s+/);
        if (fields.length < 6 || seen[fields[0]]) continue;
        var total = Number(fields[1]) / 1048576;
        var used = Number(fields[2]) / 1048576;
        if (!isFinite(total) || !isFinite(used) || total < 20 || used < 0) continue;
        seen[fields[0]] = true;
        found.push({ mount: fields[5], device: fields[0].split("/").pop(),
            usedGb: used, totalGb: total });
    }
    return found;
}
