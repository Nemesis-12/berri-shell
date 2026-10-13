.pragma library

// Sizes in the System tab are binary (GiB, MiB/s), so the labels are binary too.
/** Label next to a network rate. */
var rateUnit = "MiB/S";

/** Format a measured sensor value, or show a placeholder when unavailable. */
function sensor(value, unit, decimals) {
    return value === null ? "-" : value.toFixed(decimals) + unit;
}

/** Whole percent for the big CPU number; a dash while the first sample is missing. */
function wholePercent(value) {
    return value === null ? "-" : String(Math.round(value));
}

/** CPU share of one process row; a dash while the first sample is missing. */
function processCpu(value) {
    if (value === null) return "-";
    return value > 0 && value < 0.05 ? "<0.05%" : value.toFixed(1) + "%";
}

/** "148 / 512 GiB" or "1.2 / 2 TiB": used over total, in TiB from 1024 GiB up. */
function usedOfTotal(usedGib, totalGib) {
    var tib = totalGib >= 1024;
    var unit = tib ? "TiB" : "GiB";
    var used = tib ? usedGib / 1024 : usedGib;
    var total = tib ? totalGib / 1024 : totalGib;
    var usedText = tib ? String(Math.round(used * 10) / 10) : String(Math.round(used));
    var totalText = tib ? String(Math.round(total * 10) / 10) : String(Math.round(total));
    return usedText + " / " + totalText + " " + unit;
}

/** "/ 16 GiB": the total next to the used memory number. */
function memoryTotal(totalGib) {
    return "/ " + Math.round(totalGib) + " GiB";
}

/** MiB/s with one decimal, none from 100 up. */
function rate(mibPerSecond) {
    return mibPerSecond >= 100 ? String(Math.round(mibPerSecond)) : mibPerSecond.toFixed(1);
}
