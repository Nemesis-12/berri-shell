.pragma library
.import "Times.js" as Times
.import "CalendarItems.js" as Items
.import "IcsText.js" as Text
.import "IcsZones.js" as Zones

/** Writes items as iCalendar text. An unchanged source date keeps its exact source line. */

var calendarProduct = "-//berri-shell//Calendar//EN";

function icsDate(key) {
    return key.replace(/-/g, "");
}

function icsDateTime(key, time) {
    return icsDate(key) + "T" + time.replace(":", "") + "00";
}

/**
 * Unchanged dates keep the exact source line, including seconds and TZID.
 * Edited dates keep DATE, floating, UTC or the source zone. The new local
 * clock is converted to that zone. If conversion fails, write the instant
 * as UTC. A change between date-only and timed uses DATE or floating time.
 */
function dateProp(name, key, time, source, localZone) {
    if (source && source.date === key && source.time === time && source.raw && source.raw.split(/[;:]/)[0] === name)
        return source.raw;
    if (time === null) return name + ";VALUE=DATE:" + icsDate(key);
    if (!source || source.form === "date" || source.form === "floating") return name + ":" + icsDateTime(key, time);
    var local = new Date(+key.slice(0, 4), +key.slice(5, 7) - 1, +key.slice(8, 10), +time.slice(0, 2), +time.slice(3, 5));
    if (source.form === "zone") {
        var value = Zones.zoneClock(local.getTime(), source.tzid, localZone);
        if (value) return name + ";TZID=" + (/[:;,]/.test(source.tzid) ? '"' + source.tzid + '"' : source.tzid) + ":" + value;
    }
    return name + ":" + Zones.utcClock(local.getTime()) + "Z";
}

/** The UNTIL value: the source text when unchanged, else a date or an end-of-day clock in the source form. */
function untilValue(item) {
    var source = item.sourceDates && item.sourceDates.until;
    var start = item.sourceDates && item.sourceDates.start;
    if (source && source.date === item.until) return source.value;
    if (item.time === null) return icsDate(item.until);
    var inUtc = (source && source.form === "utc") || (start && (start.form === "utc" || start.form === "zone"));
    if (!inUtc) return icsDate(item.until) + "T235959";
    var end = new Date(+item.until.slice(0, 4), +item.until.slice(5, 7) - 1, +item.until.slice(8, 10), 23, 59, 59);
    return Zones.utcClock(end.getTime()) + "Z";
}

function ruleText(item) {
    var parts = ["FREQ=" + item.repeat.toUpperCase()];
    if (item.interval > 1) parts.push("INTERVAL=" + item.interval);
    if (item.repeat === "weekly" && item.byDay.length) parts.push("BYDAY=" + item.byDay.map(function (d) { return Text.weekdays[d]; }).join(","));
    if (item.repeat === "monthly" && item.monthWeekday) parts.push("BYDAY=" + item.monthWeekday.nth + Text.weekdays[item.monthWeekday.day]);
    if (item.count) parts.push("COUNT=" + item.count);
    else if (item.until) parts.push("UNTIL=" + untilValue(item));
    if (item.ruleRest) parts.push(item.ruleRest);
    return parts.join(";");
}

/** DTSTART and DTEND, or DUE for a task. Source lines are kept when nothing changed. */
function dateLines(item, isTodo, localZone) {
    var lines = [];
    var sources = item.sourceDates || {};
    if (!item.date) return lines;
    // A task imported with DUE alone must not gain a different DTSTART.
    if (sources.start || !sources.end || !isTodo) lines.push(dateProp("DTSTART", item.date, item.time, sources.start, localZone));
    var lastDay = item.endDate || item.date;
    var endSource = sources.end || sources.start;
    if (isTodo) {
        lines.push(dateProp("DUE", lastDay, item.time === null ? null : (item.end || item.time), endSource, localZone));
    } else if (item.time === null) {
        lines.push(dateProp("DTEND", Items.addDays(lastDay, 1), null, sources.end, localZone));
    } else if (item.end) {
        lines.push(dateProp("DTEND", lastDay, item.end, endSource, localZone));
    } else if (sources.end && sources.start && sources.start.date === item.date && sources.start.time === item.time &&
        sources.end.date === lastDay && sources.end.time === item.time) {
        lines.push(sources.end.raw);
    }
    return lines;
}

/** EXDATE lines. A source line is kept while all its dates are still excluded. */
function exdateLines(item, localZone) {
    var lines = [];
    var sources = item.sourceDates || {};
    var pending = item.exdates.slice();
    var saved = sources.exdates || [];
    for (var ex = 0; ex < saved.length; ex++) {
        var group = saved[ex];
        if (!group.values.every(function (v) { return pending.indexOf(v.date) >= 0; })) continue;
        lines.push(group.raw);
        pending = pending.filter(function (d) { return !group.values.some(function (v) { return v.date === d; }); });
    }
    if (!item.sourceDates) {
        lines.push("EXDATE" + (item.time === null ? ";VALUE=DATE" : "") + ":" + pending.map(function (d) {
            return item.time === null ? icsDate(d) : icsDateTime(d, item.time);
        }).join(","));
    } else {
        for (var e = 0; e < pending.length; e++)
            lines.push(dateProp("EXDATE", pending[e], item.time, sources.start, localZone));
    }
    return lines;
}

/** STATUS: a task is always written, an event only for a status other than COMPLETED. */
function statusLines(item, isTodo, recurring) {
    var completed = item.date !== null && item.doneDates.indexOf(item.date) >= 0 && !recurring;
    var kept = item.status && item.status !== "COMPLETED" ? item.status : null;
    if (isTodo) return ["STATUS:" + (completed ? "COMPLETED" : (kept || "NEEDS-ACTION"))];
    return kept ? ["STATUS:" + kept] : [];
}

function alarmLines(item) {
    if (item.alarmMinutes === null) return [];
    return ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + Text.escapeText(item.title),
        "TRIGGER:" + (item.alarmMinutes > 0 ? "-PT" + item.alarmMinutes + "M" : "PT0S"), "END:VALARM"];
}

function itemLines(item, localZone) {
    var isTodo = item.kind === "task";
    var name = isTodo ? "VTODO" : "VEVENT";
    var recurring = item.repeat !== "none";
    var lines = ["BEGIN:" + name, "UID:" + item.uid, "DTSTAMP:" + (item.stamp || Items.stampNow()), "SUMMARY:" + Text.escapeText(item.title)];
    appendLines(lines, dateLines(item, isTodo, localZone));
    if (recurring) lines.push("RRULE:" + ruleText(item));
    else if (item.ruleRest) lines.push("RRULE:" + item.ruleRest);
    if (item.exdates.length) appendLines(lines, exdateLines(item, localZone));
    if (item.color !== "accent") lines.push("X-BERRI-COLOR:" + item.color);
    appendLines(lines, statusLines(item, isTodo, recurring));
    if (item.kind === "reminder") lines.push("X-BERRI-KIND:reminder");
    if (item.doneDates.length && !(isTodo && !recurring)) lines.push("X-BERRI-DONE:" + item.doneDates.map(icsDate).join(","));
    appendLines(lines, item.raw);
    appendLines(lines, alarmLines(item));
    for (var c = 0; c < item.rawChildren.length; c++) appendLines(lines, item.rawChildren[c]);
    lines.push("END:" + name);
    return lines;
}

/** Adds `extra` to the end of `lines` in place. Repeated concat would copy all earlier lines each time. */
function appendLines(lines, extra) {
    for (var i = 0; i < extra.length; i++) lines.push(extra[i]);
}

/** Writes a calendar as iCalendar text (CRLF lines, folded at 75 octets). */
function writeCalendar(cal, localZone) {
    var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:" + (cal.prodid || calendarProduct)];
    appendLines(lines, cal.raw);
    for (var r = 0; r < cal.rawComponents.length; r++) appendLines(lines, cal.rawComponents[r]);
    for (var i = 0; i < cal.items.length; i++) appendLines(lines, itemLines(cal.items[i], localZone));
    lines.push("END:VCALENDAR");
    return lines.map(Text.foldLine).join("\r\n") + "\r\n";
}
