.pragma library
.import "Times.js" as Times

// Small text helpers for the weather tab. Times come from Weather as
// milliseconds or as ISO text; both are accepted.

// Milliseconds, "2026-09-30T07:18", "2026-09-30" or "07:18" (today) -> local Date.
function toDate(v) {
    if (v instanceof Date) return v;
    if (typeof v === "number") return new Date(v);
    if (typeof v === "string") {
        if (v.length === 5 && v.charAt(2) === ":") {
            var t = new Date();
            t.setHours(parseInt(v.slice(0, 2)), parseInt(v.slice(3, 5)), 0, 0);
            return t;
        }
        if (v.length === 10) {
            var p = v.split("-");
            return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
        }
        return new Date(v);
    }
    return new Date(NaN);
}

// "3:05 PM" or, with clock24, "15:05". Empty text for a missing time.
function clock(v, clock24) {
    var d = toDate(v);
    if (isNaN(d.getTime())) return "";
    return Times.clockOfDate(d, clock24);
}

// Hour label for the strip: "3P" or, with clock24, "15".
function hourLabel(v, clock24) {
    var h = toDate(v).getHours();
    if (clock24) return Times.pad(h);
    return ((h % 12) || 12) + (h < 12 ? "A" : "P");
}

// Uppercase day name for the weather column and card.
function weekday(v) {
    var name = Times.weekdaysShort[toDate(v).getDay()];
    return name === undefined ? undefined : name.toUpperCase();
}

// Wind direction: 8 points for display, 16 for parsed data; text stays as is.
function compass(v, points) {
    if (typeof v === "string") return v;
    var names = points === 16
        ? ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        : ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    return names[Math.round(((v % 360) + 360) % 360 / (360 / names.length)) % names.length];
}

// Millimetres with one decimal, "0" when dry.
function millimetres(v) {
    return v > 0 ? (Math.round(v * 10) / 10).toString() : "0";
}

// Text of the stale-data chip: "NO DATA" before the first good reading,
// otherwise the age of `updatedAt` at `now` (both ms): "JUST NOW", "5 M AGO", "2 H AGO", "3 D AGO".
function staleChip(updatedAt, now) {
    if (!updatedAt) return "NO DATA";
    var age = Times.ageText(updatedAt, now, "shortCaps");
    return age === "NOW" ? "JUST NOW" : age.replace(/^(\d+)([MHD])$/, "$1 $2 AGO");
}
