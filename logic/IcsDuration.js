.pragma library

/** Reads iCalendar durations for event lengths and relative alarms. */
function readDuration(value) {
    var text = value.trim();
    var m = /^([+-]?)P(?:(\d+)W|(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)$/.exec(text);
    if (!m || !m.slice(2).some(function (v) { return v !== undefined; }) || /T$/.test(text)) return null;
    var days = (+m[2] || 0) * 7 + (+m[3] || 0);
    var seconds = (+m[4] || 0) * 3600 + (+m[5] || 0) * 60 + (+m[6] || 0);
    if (days * 86400 + seconds > 9007199254740991) return null;
    return { days: days, seconds: seconds, negative: m[1] === "-" };
}
