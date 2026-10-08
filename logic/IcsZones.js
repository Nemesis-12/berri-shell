.pragma library
.import "Times.js" as Times

/** Clock text and time-zone conversion for iCalendar date-times. */

/** UTC clock fields as an iCalendar date-time, without the Z suffix. */
function utcClock(ms) {
    var d = new Date(ms);
    return Times.pad(d.getUTCFullYear(), 4) + Times.pad(d.getUTCMonth() + 1) + Times.pad(d.getUTCDate()) + "T" +
        Times.pad(d.getUTCHours()) + Times.pad(d.getUTCMinutes()) + Times.pad(d.getUTCSeconds());
}

function clockMs(value) {
    return Date.UTC(+value.slice(0, 4), +value.slice(4, 6) - 1, +value.slice(6, 8),
        +value.slice(9, 11), +value.slice(11, 13), +value.slice(13, 15) || 0);
}

/** Node uses Intl. QML supplies Date.fromLocaleString with the named zone. */
function zoneInstant(value, zone, localZone) {
    try {
        if (localZone) return localZone(value, zone);
        if (typeof Intl === "undefined") return NaN;
        var formatter = new Intl.DateTimeFormat("en-CA", {
            timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
            hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23"
        });
        var wall = clockMs(value);
        var offsets = [];
        for (var day = -1; day <= 1; day++) {
            var sample = wall + day * 86400000;
            var parts = {};
            formatter.formatToParts(new Date(sample)).forEach(function (p) { parts[p.type] = p.value; });
            var offset = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second) - sample;
            if (offsets.indexOf(offset) < 0) offsets.push(offset);
        }
        // A repeated clock time uses the first instant. A gap uses the earlier offset.
        var matches = [];
        for (var i = 0; i < offsets.length; i++) {
            var candidate = wall - offsets[i];
            var fields = {};
            formatter.formatToParts(new Date(candidate)).forEach(function (p) { fields[p.type] = p.value; });
            if (Date.UTC(+fields.year, +fields.month - 1, +fields.day, +fields.hour, +fields.minute, +fields.second) === wall)
                matches.push(candidate);
        }
        return matches.length ? Math.min.apply(null, matches) : wall - offsets[0];
    } catch (e) { return NaN; }
}

/** Converts an instant to a zone clock using the same zone reader as parse. */
function zoneClock(ms, zone, localZone) {
    var wall = ms;
    for (var i = 0; i < 4; i++) {
        var text = utcClock(wall);
        var instant = zoneInstant(text, zone, localZone);
        if (!isFinite(instant)) return null;
        if (instant === ms) return text;
        wall += ms - instant;
    }
    return null;
}
