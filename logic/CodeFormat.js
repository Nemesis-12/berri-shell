.pragma library
.import "Times.js" as Times

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** 1210000 -> "1.21M", 7300 -> "7.3K", 42 -> "42". The unit follows the rounded value: 999999 -> "1.00M". */
function tokens(n) {
    if (n >= 99.995e6) return Math.round(n / 1e6) + "M";
    if (n >= 999500) return (n / 1e6).toFixed(2) + "M";
    if (n >= 99950) return Math.round(n / 1e3) + "K";
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K";
    return String(Math.round(n));
}

/** Estimated cost: 12.4 -> "$12.40", 1234 -> "$1.2K", 999.996 -> "$1.0K". */
function cost(usd) {
    if (Math.round(usd * 100) >= 100000) return "$" + (usd / 1000).toFixed(1) + "K";
    return "$" + usd.toFixed(2);
}

/** "2026-09-28" -> local Date (a plain Date("YYYY-MM-DD") would read it as UTC). */
function localDate(iso) {
    var p = iso.split("-");
    return new Date(+p[0], +p[1] - 1, +p[2]);
}

/** Time left until `at` (Date), like "3D 4H" or "2H 05M" (Times.duration); "--" when unknown or passed. */
function timeLeft(at, now) {
    if (!at || isNaN(at.getTime())) return "--";
    var ms = at.getTime() - now.getTime();
    if (!(ms > 0)) return "--";
    return Times.duration(ms / 1000);
}

/** "12m ago", "3h ago", "yesterday", "5d ago" or "Sep 14". */
function ago(date, now) {
    return Times.ageText(date.getTime(), now.getTime(), "agoOrDate");
}

/** Heat level 0..4 for a day's contribution count. */
function heatLevel(count) {
    return count === 0 ? 0 : count <= 2 ? 1 : count <= 5 ? 2 : count <= 8 ? 3 : 4;
}
