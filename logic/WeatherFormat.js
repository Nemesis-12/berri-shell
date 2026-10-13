.pragma library
.import "Times.js" as Times

// Small text helpers for the weather tab. Times come from Weather as
// milliseconds or as ISO text; both are accepted.

// Converts weather wall time to a UTC Date used only for calendar fields.
// Numeric timestamps are host instants, such as the last refresh time.
function toDate(v) {
    if (v instanceof Date) return v;
    if (typeof v === "number") return new Date(v);
    if (typeof v !== "string" || v === "") return new Date(NaN);
    if (v.length === 5) v = "2000-01-01T" + v;
    if (v.length === 10) v += "T00:00";
    return new Date(v + "Z");
}

// Formats a remote wall clock; refresh timestamps use the host clock.
function clock(v, clock24) {
    var d = toDate(v);
    if (isNaN(d.getTime())) return "";
    if (typeof v === "number") return Times.clockOfDate(d, clock24);
    return Times.clockText(Times.pad(d.getUTCHours()) + ":" + Times.pad(d.getUTCMinutes()), clock24);
}

// Hour label for the strip: "3P" or, with clock24, "15".
function hourLabel(v, clock24) {
    var h = toDate(v).getUTCHours();
    if (clock24) return Times.pad(h);
    return ((h % 12) || 12) + (h < 12 ? "A" : "P");
}

// Uppercase day name for the weather column and card.
function weekday(v) {
    var name = Times.weekdaysShort[toDate(v).getUTCDay()];
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
