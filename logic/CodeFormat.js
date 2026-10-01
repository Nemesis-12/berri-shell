.pragma library
.import "Times.js" as Times

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** 1210000 -> "1.21M", 7300 -> "7.3K", 42 -> "42". */
function tokens(n) {
    if (n >= 100e6) return Math.round(n / 1e6) + "M";
    if (n >= 1e6) return (n / 1e6).toFixed(2) + "M";
    if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e5 ? 0 : 1) + "K";
    return String(Math.round(n));
}

/** Estimated cost: 12.4 -> "$12.40", 1234 -> "$1.2K". */
function cost(usd) {
    if (usd >= 1000) return "$" + (usd / 1000).toFixed(1) + "K";
    return "$" + usd.toFixed(2);
}

/** "2026-09-28" -> local Date (a plain Date("YYYY-MM-DD") would read it as UTC). */
function localDate(iso) {
    var p = iso.split("-");
    return new Date(+p[0], +p[1] - 1, +p[2]);
}

/** Time left until `at` (Date), like "3d 4h" or "2h 05m"; "--" when unknown or passed. */
function timeLeft(at, now) {
    if (!at || isNaN(at.getTime())) return "--";
    var ms = at.getTime() - now.getTime();
    if (!(ms > 0)) return "--";
    var m = Math.floor(ms / 60000);
    var d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60), mi = m % 60;
    if (d > 0) return d + "d " + h + "h";
    return h + "h " + (mi < 10 ? "0" : "") + mi + "m";
}

/** "12m ago", "3h ago", "yesterday", "5d ago" or "Sep 14". */
function ago(date, now) {
    return Times.ageText(date.getTime(), now.getTime(), "agoOrDate");
}

/** Heat level 0..4 for a day's contribution count. */
function heatLevel(count) {
    return count === 0 ? 0 : count <= 2 ? 1 : count <= 5 ? 2 : count <= 8 ? 3 : 4;
}
