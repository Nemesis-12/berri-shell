.pragma library

// Pure parser for a "/proc/meminfo" dump. The one place that reads these
// fields; SystemUsage (Home rings) and SystemStats (System tab) both call it.
// No QML types, so node can test it.

function kilobytes(text, key) {
    var match = text.match(new RegExp("^" + key + ":\\s*(\\d+)", "m"));
    return match ? Number(match[1]) : -1;
}

/** Returns { totalGb, usedGb, percent, swapTotalGb, swapUsedGb }, or null if MemTotal or MemAvailable is missing. Sizes are GiB. */
function readMemoryUse(text) {
    var total = kilobytes(text, "MemTotal");
    var available = kilobytes(text, "MemAvailable");
    if (total <= 0 || available < 0) return null;
    var swapTotal = Math.max(0, kilobytes(text, "SwapTotal"));
    var swapFree = Math.max(0, kilobytes(text, "SwapFree"));
    var gib = 1048576;
    return {
        totalGb: total / gib,
        usedGb: (total - available) / gib,
        percent: Math.max(0, Math.min(100, 100 * (total - available) / total)),
        swapTotalGb: swapTotal / gib,
        swapUsedGb: (swapTotal - swapFree) / gib
    };
}
