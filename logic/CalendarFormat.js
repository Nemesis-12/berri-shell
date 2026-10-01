.pragma library
.import "Times.js" as Times
.import "CalendarItems.js" as Items

/** Reads and writes calendar text while keeping unknown fields and source dates. */

var repeatNames = { DAILY: "daily", WEEKLY: "weekly", MONTHLY: "monthly", YEARLY: "yearly" };
var weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
var calendarProduct = "-//berri-shell//Calendar//EN";
var oldTagColors = { personal: "accent", work: "blue", health: "green", home: "yellow" };

function utf8Length(str, index) {
    var c = str.charCodeAt(index);
    if (c < 0x80) return 1;
    if (c < 0x800) return 2;
    if (c >= 0xd800 && c <= 0xdbff) return 4; // surrogate pair, counted on the first half
    if (c >= 0xdc00 && c <= 0xdfff) return 0;
    return 3;
}

/** Folds one line to at most 75 octets per physical line, never inside a character. */
function foldLine(line) {
    var out = [];
    var current = "";
    var bytes = 0;
    var limit = 75;
    for (var i = 0; i < line.length; i++) {
        var w = utf8Length(line, i);
        if (bytes + w > limit) {
            out.push(current);
            current = " ";
            bytes = 1;
            limit = 75;
        }
        current += line.charAt(i);
        bytes += w;
    }
    out.push(current);
    return out.join("\r\n");
}

/** Joins folded lines. Empty lines are dropped. */
function unfold(text) {
    var physical = text.split(/\r\n|\n|\r/);
    var lines = [];
    for (var i = 0; i < physical.length; i++) {
        var line = physical[i];
        var first = line.charAt(0);
        if ((first === " " || first === "\t") && lines.length > 0) lines[lines.length - 1] += line.substring(1);
        else if (line !== "") lines.push(line);
    }
    return lines;
}

function escapeText(text) {
    return String(text).replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r\n|\r|\n/g, "\\n");
}

/** Splits on a separator that is not escaped with a backslash. */
function splitUnescaped(text, sep) {
    var parts = [];
    var current = "";
    for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i);
        if (ch === "\\" && i + 1 < text.length) { current += ch + text.charAt(++i); }
        else if (ch === sep) { parts.push(current); current = ""; }
        else current += ch;
    }
    parts.push(current);
    return parts;
}

function unescapeText(text) {
    return text.replace(/\\([\\;,nN])/g, function (all, c) {
        return (c === "n" || c === "N") ? "\n" : c;
    });
}

/** Splits a content line into { name, params, value, raw }. Quotes may hide ":" and ";". */
function parseLine(line) {
    var inQuote = false;
    var sep = -1;
    var cuts = [];
    for (var i = 0; i < line.length; i++) {
        var ch = line.charAt(i);
        if (ch === '"') inQuote = !inQuote;
        else if (!inQuote && ch === ";" && sep < 0) cuts.push(i);
        else if (!inQuote && ch === ":") { sep = i; break; }
    }
    if (sep < 0) return { name: line.toUpperCase(), params: {}, value: "", raw: line };
    var head = line.slice(0, sep);
    var pieces = [];
    var from = 0;
    for (var c = 0; c < cuts.length; c++) {
        pieces.push(line.slice(from, cuts[c]));
        from = cuts[c] + 1;
    }
    pieces.push(line.slice(from, sep));
    var params = {};
    for (var p = 1; p < pieces.length; p++) {
        var eq = pieces[p].indexOf("=");
        if (eq > 0) params[pieces[p].slice(0, eq).toUpperCase()] = pieces[p].slice(eq + 1).replace(/^"|"$/g, "");
    }
    return { name: pieces[0].toUpperCase(), params: params, value: line.slice(sep + 1), raw: line };
}

/** Turns unfolded lines into nested components: { name, props, children, lines }. */
function parseComponents(lines) {
    var roots = [];
    var stack = [];
    for (var i = 0; i < lines.length; i++) {
        var upper = lines[i].toUpperCase();
        if (upper.indexOf("BEGIN:") === 0) {
            var node = { name: upper.slice(6), props: [], children: [], start: i, lines: [] };
            if (stack.length) stack[stack.length - 1].children.push(node);
            else roots.push(node);
            stack.push(node);
        } else if (upper.indexOf("END:") === 0) {
            var done = stack.pop();
            if (done) done.lines = lines.slice(done.start, i + 1);
        } else if (stack.length) {
            stack[stack.length - 1].props.push(parseLine(lines[i]));
        }
    }
    return roots;
}

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

/** Reads a date for local display and keeps its source form and instant. */
function parseDateValue(value, params, localZone) {
    var text = value.trim();
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/.exec(text);
    if (!m) return null;
    var date = m[1] + "-" + m[2] + "-" + m[3];
    var zone = params && params.TZID ? params.TZID : null;
    var form = m[4] === undefined ? "date" : m[7] ? "utc" : zone ? "zone" : "floating";
    var instant = null;
    var time = m[4] === undefined ? null : m[4] + ":" + m[5];
    if (form !== "date") {
        if (form === "utc") instant = clockMs(text);
        else if (form === "zone") instant = zoneInstant(text, zone, localZone);
        else instant = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6] || 0).getTime();
        if (isFinite(instant)) {
            var local = new Date(instant);
            date = Items.toKey(local);
            time = Times.pad(local.getHours()) + ":" + Times.pad(local.getMinutes());
        } else instant = null;
    }
    return { date: date, time: time, form: form, tzid: form === "zone" ? zone : null,
        value: text, instantMs: instant };
}

function parseDateProperty(p, localZone) {
    var source = parseDateValue(p.value, p.params, localZone);
    if (source) source.raw = p.raw;
    return source;
}

function parseRule(value, item, localZone) {
    var rest = [];
    var parts = value.split(";");
    var freq = null;
    for (var i = 0; i < parts.length; i++) {
        var eq = parts[i].indexOf("=");
        var k = (eq > 0 ? parts[i].slice(0, eq) : parts[i]).toUpperCase();
        var v = eq > 0 ? parts[i].slice(eq + 1) : "";
        if (k === "FREQ") freq = repeatNames[v.toUpperCase()] || null;
        else if (k === "INTERVAL") item.interval = Math.max(1, parseInt(v, 10) || 1);
        else if (k === "COUNT") item.count = parseInt(v, 10) || null;
        else if (k === "UNTIL") { var u = parseDateValue(v, null, localZone); item.until = u ? u.date : null; item.untilSource = u; }
        else if (k === "BYDAY" && /^(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*$/i.test(v)) {
            item.byDay = v.toUpperCase().split(",").map(function (d) { return weekdays.indexOf(d); });
        } else rest.push(parts[i]);
    }
    return { freq: freq, rest: rest };
}

function parseAlarm(node) {
    // Only the simple form berri writes is taken over; anything else stays raw.
    var trigger = null, action = null, extra = false;
    for (var i = 0; i < node.props.length; i++) {
        var p = node.props[i];
        if (p.name === "TRIGGER") trigger = p;
        else if (p.name === "ACTION") action = p.value.toUpperCase();
        else if (p.name !== "DESCRIPTION") extra = true;
    }
    if (extra || node.children.length || action !== "DISPLAY" || !trigger) return null;
    if (trigger.params.VALUE && trigger.params.VALUE.toUpperCase() !== "DURATION") return null;
    if (trigger.params.RELATED && trigger.params.RELATED.toUpperCase() !== "START") return null;
    var m = /^(-?)P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(trigger.value.trim());
    if (!m) return null;
    var minutes = (+m[2] || 0) * 10080 + (+m[3] || 0) * 1440 + (+m[4] || 0) * 60 + (+m[5] || 0);
    if (m[1] !== "-" && minutes > 0) return null; // alarm after the start
    return minutes;
}

function parseItem(node, localZone) {
    var isTodo = node.name === "VTODO";
    var item = {
        uid: "", kind: isTodo ? "task" : "event", title: "",
        date: null, time: null, end: null, endDate: null,
        color: "accent", repeat: "none", interval: 1, byDay: [], until: null, count: null,
        exdates: [], doneDates: [], alarmMinutes: null, status: null, stamp: null, ruleRest: null,
        raw: [], rawChildren: []
    };
    var start = null, endValue = null, sawDoneCompleted = false;
    var sourceDates = { start: null, end: null, until: null, exdates: [] };
    var ownColor = null, legacyColor = null;
    for (var i = 0; i < node.props.length; i++) {
        var p = node.props[i];
        switch (p.name) {
        case "UID": item.uid = p.value; break;
        case "DTSTAMP": item.stamp = p.value; break;
        case "SUMMARY": item.title = unescapeText(p.value); break;
        case "DTSTART": start = parseDateProperty(p, localZone); if (!start) item.raw.push(p.raw); break;
        case "DTEND": case "DUE":
            if (p.name === (isTodo ? "DUE" : "DTEND")) {
                endValue = parseDateProperty(p, localZone);
                if (!endValue) item.raw.push(p.raw);
            } else item.raw.push(p.raw);
            break;
        case "CATEGORIES": {
            var oldColor = oldTagColors[p.value.trim().toLowerCase()];
            if (oldColor) legacyColor = oldColor; // old berri tag, replaced by X-BERRI-COLOR
            else item.raw.push(p.raw);
            break;
        }
        case "X-BERRI-COLOR": ownColor = p.value.trim(); break;
        case "RRULE": {
            var repeatRule = { interval: 1, byDay: [], until: null, count: null };
            var rule = parseRule(p.value, repeatRule, localZone);
            if (!rule.freq || item.repeat !== "none") { item.raw.push(p.raw); break; }
            item.repeat = rule.freq;
            item.interval = repeatRule.interval;
            item.byDay = repeatRule.byDay;
            item.until = repeatRule.until;
            sourceDates.until = repeatRule.untilSource || null;
            item.count = repeatRule.count;
            item.ruleRest = rule.rest.length ? rule.rest.join(";") : null; // rule parts berri ignores, written back as they were
            break;
        }
        case "EXDATE":
            var sources = [];
            p.value.split(",").forEach(function (v) {
                var d = parseDateValue(v, p.params, localZone);
                if (d) { item.exdates.push(d.date); sources.push(d); }
            });
            sourceDates.exdates.push({ raw: p.raw, values: sources });
            break;
        case "STATUS":
            // COMPLETED and NEEDS-ACTION are derived from the done dates when written.
            if (p.value.toUpperCase() === "COMPLETED") sawDoneCompleted = true;
            else if (p.value.toUpperCase() !== "NEEDS-ACTION") item.status = p.value.toUpperCase();
            break;
        case "X-BERRI-KIND": if (p.value.toLowerCase() === "reminder") item.kind = "reminder"; break;
        case "X-BERRI-DONE":
            p.value.split(",").forEach(function (v) {
                var d = parseDateValue(v);
                if (d) item.doneDates.push(d.date);
            });
            break;
        default: item.raw.push(p.raw);
        }
    }
    if (start) {
        item.date = start.date;
        item.time = start.time;
    } else if (endValue) {
        item.date = endValue.date;
        item.time = endValue.time;
    }
    if (start && endValue) {
        if (start.time === null) {
            // All-day: VEVENT DTEND is exclusive, VTODO DUE is inclusive.
            var last = isTodo ? endValue.date : Items.addDays(endValue.date, -1);
            item.endDate = Times.dayNum(last) > Times.dayNum(start.date) ? last : null;
        } else if (endValue.time !== null) {
            if (endValue.time !== start.time || endValue.date !== start.date) item.end = endValue.time;
            if (endValue.date !== start.date) item.endDate = endValue.date;
        }
    }
    sourceDates.start = start;
    sourceDates.end = endValue;
    item.sourceDates = sourceDates;
    if (item.uid === "") item.uid = Items.newUid();

    // Children: the one simple VALARM is taken over, the rest stays raw.
    for (var c = 0; c < node.children.length; c++) {
        var child = node.children[c];
        var minutes = (child.name === "VALARM" && item.alarmMinutes === null) ? parseAlarm(child) : null;
        if (minutes !== null) item.alarmMinutes = minutes;
        else item.rawChildren.push(child.lines);
    }
    if (sawDoneCompleted && item.repeat === "none" && item.date && item.doneDates.indexOf(item.date) < 0) item.doneDates.push(item.date);
    item.color = Items.cleanColor(ownColor) || legacyColor || "accent";
    return item;
}

/** Parses the text of one .ics file. Never throws; garbage gives an empty calendar. */
function readCalendar(text, localZone) {
    var cal = { prodid: null, raw: [], rawComponents: [], items: [] };
    var roots = parseComponents(unfold(text || ""));
    for (var r = 0; r < roots.length; r++) {
        var root = roots[r];
        if (root.name !== "VCALENDAR") continue;
        for (var i = 0; i < root.props.length; i++) {
            var p = root.props[i];
            if (p.name === "VERSION") continue;
            if (p.name === "PRODID") cal.prodid = cal.prodid || p.value;
            else cal.raw.push(p.raw);
        }
        for (var c = 0; c < root.children.length; c++) {
            var node = root.children[c];
            var hasOverride = node.props.some(function (q) { return q.name === "RECURRENCE-ID"; });
            if ((node.name === "VEVENT" || node.name === "VTODO") && !hasOverride) cal.items.push(parseItem(node, localZone));
            else cal.rawComponents.push(node.lines);
        }
    }
    return cal;
}

function expandCompactItem(record) {
    return { uid: record.uid, kind: record.kind, title: record.title, location: record.location,
        date: record.date, time: record.time, end: record.end, endDate: record.endDate,
        color: record.color, repeat: record.repeat, interval: record.interval,
        byDay: record.byDay || [], until: record.until, count: record.count,
        exdates: record.exdates || [], doneDates: record.doneDates || [],
        alarmMinutes: record.alarmMinutes, status: record.status };
}

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
        var value = zoneClock(local.getTime(), source.tzid, localZone);
        if (value) return name + ";TZID=" + (/[:;,]/.test(source.tzid) ? '"' + source.tzid + '"' : source.tzid) + ":" + value;
    }
    return name + ":" + utcClock(local.getTime()) + "Z";
}

function ruleText(item, localZone) {
    var parts = ["FREQ=" + item.repeat.toUpperCase()];
    if (item.interval > 1) parts.push("INTERVAL=" + item.interval);
    if (item.repeat === "weekly" && item.byDay.length) parts.push("BYDAY=" + item.byDay.map(function (d) { return weekdays[d]; }).join(","));
    if (item.count) parts.push("COUNT=" + item.count);
    else if (item.until) {
        var source = item.sourceDates && item.sourceDates.until;
        var start = item.sourceDates && item.sourceDates.start;
        var value;
        if (source && source.date === item.until) value = source.value;
        else if (item.time === null) value = icsDate(item.until);
        else if (source && source.form === "utc" || start && (start.form === "utc" || start.form === "zone")) {
            var end = new Date(+item.until.slice(0, 4), +item.until.slice(5, 7) - 1, +item.until.slice(8, 10), 23, 59, 59);
            value = utcClock(end.getTime()) + "Z";
        } else value = icsDate(item.until) + "T235959";
        parts.push("UNTIL=" + value);
    }
    if (item.ruleRest) parts.push(item.ruleRest);
    return parts.join(";");
}

function itemLines(item, localZone) {
    var isTodo = item.kind === "task";
    var name = isTodo ? "VTODO" : "VEVENT";
    var recurring = item.repeat !== "none";
    var lines = ["BEGIN:" + name, "UID:" + item.uid, "DTSTAMP:" + (item.stamp || Items.stampNow()), "SUMMARY:" + escapeText(item.title)];
    var sources = item.sourceDates || {};
    if (item.date) {
        // A task imported with DUE alone must not gain a different DTSTART.
        if (sources.start || !sources.end || !isTodo) lines.push(dateProp("DTSTART", item.date, item.time, sources.start, localZone));
        var lastDay = item.endDate || item.date;
        if (isTodo) {
            lines.push(dateProp("DUE", lastDay, item.time === null ? null : (item.end || item.time), sources.end || sources.start, localZone));
        } else if (item.time === null) {
            lines.push(dateProp("DTEND", Items.addDays(lastDay, 1), null, sources.end, localZone));
        } else if (item.end) {
            lines.push(dateProp("DTEND", lastDay, item.end, sources.end || sources.start, localZone));
        } else if (sources.end && sources.start && sources.start.date === item.date && sources.start.time === item.time &&
            sources.end.date === lastDay && sources.end.time === item.time) {
            lines.push(sources.end.raw);
        }
    }
    if (recurring) lines.push("RRULE:" + ruleText(item, localZone));
    else if (item.ruleRest) lines.push("RRULE:" + item.ruleRest);
    if (item.exdates.length) {
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
    }
    if (item.color !== "accent") lines.push("X-BERRI-COLOR:" + item.color);
    var completed = item.date !== null && item.doneDates.indexOf(item.date) >= 0 && !recurring;
    if (isTodo) lines.push("STATUS:" + (completed ? "COMPLETED" : (item.status && item.status !== "COMPLETED" ? item.status : "NEEDS-ACTION")));
    else if (item.status && item.status !== "COMPLETED") lines.push("STATUS:" + item.status);
    if (item.kind === "reminder") lines.push("X-BERRI-KIND:reminder");
    if (item.doneDates.length && !(isTodo && !recurring)) lines.push("X-BERRI-DONE:" + item.doneDates.map(icsDate).join(","));
    for (var i = 0; i < item.raw.length; i++) lines.push(item.raw[i]);
    if (item.alarmMinutes !== null) {
        lines.push("BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + escapeText(item.title),
            "TRIGGER:" + (item.alarmMinutes > 0 ? "-PT" + item.alarmMinutes + "M" : "PT0S"), "END:VALARM");
    }
    for (var c = 0; c < item.rawChildren.length; c++) lines = lines.concat(item.rawChildren[c]);
    lines.push("END:" + name);
    return lines;
}

/** Writes a calendar as iCalendar text (CRLF lines, folded at 75 octets). */
function writeCalendar(cal, localZone) {
    var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:" + (cal.prodid || calendarProduct)].concat(cal.raw);
    for (var r = 0; r < cal.rawComponents.length; r++) lines = lines.concat(cal.rawComponents[r]);
    for (var i = 0; i < cal.items.length; i++) lines = lines.concat(itemLines(cal.items[i], localZone));
    lines.push("END:VCALENDAR");
    return lines.map(foldLine).join("\r\n") + "\r\n";
}

function emptyCalendar() {
    return { prodid: null, raw: [], rawComponents: [], items: [] };
}
