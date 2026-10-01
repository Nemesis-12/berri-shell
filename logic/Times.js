.pragma library

/** The one home of date and time text: padding, day keys, clocks, ages and names. */

var monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
var monthsLong = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"];
/** Index 0 is Sunday. */
var weekdaysShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var weekdaysLong = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

/** 5 -> "05"; width is 2 unless given. */
function pad(n, width) {
    var s = String(n);
    while (s.length < (width || 2)) s = "0" + s;
    return s;
}

/** Local calendar day of a Date as "YYYY-MM-DD". */
function dayKey(date) {
    return pad(date.getFullYear(), 4) + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
}

/** Day number (days since 1970-01-01) of a "YYYY-MM-DD" key. */
function dayNum(key) {
    return Math.floor(Date.UTC(+key.slice(0, 4), +key.slice(5, 7) - 1, +key.slice(8, 10)) / 86400000);
}

/** The "YYYY-MM-DD" key of a day number. */
function keyOfDayNum(n) {
    var d = new Date(n * 86400000);
    return pad(d.getUTCFullYear(), 4) + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate());
}

/** Seconds -> "3:07". Missing or negative seconds count as 0. */
function minutesSeconds(seconds) {
    var total = Math.max(0, Math.floor(seconds || 0));
    return Math.floor(total / 60) + ":" + pad(total % 60);
}

/** "15:05" -> "3:05 PM", or "15:05" with clock24. Empty text for empty input. */
function clockText(hm, clock24) {
    if (!hm) return "";
    var h = parseInt(hm.slice(0, 2), 10);
    var m = hm.slice(3, 5);
    if (clock24) return pad(h) + ":" + m;
    return ((h % 12) || 12) + ":" + m + " " + (h < 12 ? "AM" : "PM");
}

/** Clock text of a Date's time of day, like clockText. */
function clockOfDate(date, clock24) {
    return clockText(pad(date.getHours()) + ":" + pad(date.getMinutes()), clock24);
}

/**
 * Age of `stamp` at `now` (both in milliseconds; a Date is also fine for
 * stamp). The style picks the wording:
 *   "short"     now, 3m, 4h                   (pop-up card)
 *   "shortCaps" NOW, 3M, 4H, 2D               (alerts list)
 *   "ago"       just now, 3m ago, 2d ago      (calendar sources; "—" without a stamp)
 *   "agoOrDate" 12m ago, yesterday, Sep 14    (code tab)
 */
function ageText(stamp, now, style) {
    var t = stamp instanceof Date ? stamp.getTime() : stamp;
    var m;
    if (style === "short") {
        m = Math.floor((now - t) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m";
        return Math.floor(m / 60) + "h";
    }
    if (style === "shortCaps") {
        m = Math.floor((now - t) / 60000);
        if (m < 1) return "NOW";
        if (m < 60) return m + "M";
        if (m < 1440) return Math.floor(m / 60) + "H";
        return Math.floor(m / 1440) + "D";
    }
    if (style === "ago") {
        if (!t) return "—";
        m = Math.max(0, Math.round((now - t) / 60000));
        if (m < 1) return "just now";
        if (m < 60) return m + "m ago";
        if (m < 1440) return Math.round(m / 60) + "h ago";
        return Math.round(m / 1440) + "d ago";
    }
    // "agoOrDate"
    m = Math.max(0, Math.floor((now - t) / 60000));
    if (m < 60) return m + "m ago";
    if (m < 1440) return Math.floor(m / 60) + "h ago";
    if (m < 2880) return "yesterday";
    if (m < 43200) return Math.floor(m / 1440) + "d ago";
    var d = new Date(t);
    return monthsShort[d.getMonth()] + " " + d.getDate();
}
