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
        counters.push({ id: fields[0], total: total, idle: Number(fields[4]) + (Number(fields[5]) || 0) });
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

/** Select CPU, GPU and fan inputs from readable hwmon files. */
function readSensors(text) {
    var result = { cpuTempPath: "", igpuTempPath: "", fanPath: "", dgpuPath: "", missing: [] };
    var cpuRank = 0, fanRank = 0;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split("\t");
        if (fields[0] === "D") { result.dgpuPath = fields[1]; continue; }
        if (fields[0] !== "S" || fields.length < 4) continue;
        var name = fields[1], path = fields[2], label = fields[3];
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
        if (fields.length < 6) continue;
        var total = Number(fields[1]) / 1048576;
        var used = Number(fields[2]) / 1048576;
        if (!isFinite(total) || !isFinite(used) || total <= 0 || used < 0 || used > total) continue;
        if (seen[fields[0]] !== undefined) {
            if (fields[5] === "/") found[seen[fields[0]]].mount = "/";
            continue;
        }
        seen[fields[0]] = found.length;
        found.push({ mount: fields[5], device: fields[0].split("/").pop(),
            usedGb: used, totalGb: total, percent: 100 * used / total });
    }
    return found.sort(function (a, b) { return (a.mount === "/" ? -1 : 0) - (b.mount === "/" ? -1 : 0); });
}
