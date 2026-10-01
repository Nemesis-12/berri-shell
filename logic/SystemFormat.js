.pragma library

/** "148 / 512 GB" or "1.2 / 2 TB": used over total, in TB from 1000 GB up. */
function usedOfTotal(usedGb, totalGb) {
    var tb = totalGb >= 1000;
    var unit = tb ? "TB" : "GB";
    var used = tb ? usedGb / 1024 : usedGb;
    var total = tb ? totalGb / 1024 : totalGb;
    var usedText = tb ? String(Math.round(used * 10) / 10) : String(Math.round(used));
    var totalText = tb ? String(Math.round(total * 10) / 10) : String(Math.round(total));
    return usedText + " / " + totalText + " " + unit;
}

/** "UP 4H 12M", or "UP 2D 3H" from a day on. */
function uptime(seconds) {
    var minutes = Math.floor(seconds / 60);
    var days = Math.floor(minutes / 1440);
    var hours = Math.floor((minutes % 1440) / 60);
    if (days > 0) return "UP " + days + "D " + hours + "H";
    return "UP " + hours + "H " + (minutes % 60) + "M";
}

/** MB/s with one decimal, none from 100 up. */
function rate(mbPerSecond) {
    return mbPerSecond >= 100 ? String(Math.round(mbPerSecond)) : mbPerSecond.toFixed(1);
}
