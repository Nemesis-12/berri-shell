.pragma library
.import "Times.js" as Times
.import "CalendarItems.js" as Items
.import "IcsText.js" as Text
.import "IcsZones.js" as Zones

/** Reads iCalendar text into items, keeping unknown fields and source dates. */

var repeatNames = { DAILY: "daily", WEEKLY: "weekly", MONTHLY: "monthly", YEARLY: "yearly" };
var oldTagColors = { personal: "accent", work: "blue", health: "green", home: "yellow" };

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
        if (form === "utc") instant = Zones.clockMs(text);
        else if (form === "zone") instant = Zones.zoneInstant(text, zone, localZone);
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
    var ordinalDay = null; // BYDAY with a week number, for example 2TU, read only when the rule is monthly
    for (var i = 0; i < parts.length; i++) {
        var eq = parts[i].indexOf("=");
        var k = (eq > 0 ? parts[i].slice(0, eq) : parts[i]).toUpperCase();
        var v = eq > 0 ? parts[i].slice(eq + 1) : "";
        if (k === "FREQ") freq = repeatNames[v.toUpperCase()] || null;
        else if (k === "INTERVAL") item.interval = Math.max(1, parseInt(v, 10) || 1);
        else if (k === "COUNT") item.count = parseInt(v, 10) || null;
        else if (k === "UNTIL") { var u = parseDateValue(v, null, localZone); item.until = u ? u.date : null; item.untilSource = u; }
        else if (k === "BYDAY" && /^(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*$/i.test(v)) {
            item.byDay = v.toUpperCase().split(",").map(function (d) { return Text.weekdays.indexOf(d); });
        } else if (k === "BYDAY" && /^[+-]?[1-5](MO|TU|WE|TH|FR|SA|SU)$/i.test(v)) {
            ordinalDay = { part: parts[i], nth: parseInt(v, 10), day: Text.weekdays.indexOf(v.slice(-2).toUpperCase()) };
        } else rest.push(parts[i]);
    }
    if (ordinalDay) {
        if (freq === "monthly") item.monthWeekday = { nth: ordinalDay.nth, day: ordinalDay.day };
        else rest.push(ordinalDay.part);
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
    if (!(minutes <= 9007199254740991)) return null; // too large to count exactly
    if (m[1] !== "-" && minutes > 0) return null; // alarm after the start
    return minutes;
}

var ZONE_SCAN_DAYS = 3660; // a zoned series is followed for ten years
var ZONE_SCAN_STEP = 21;

/**
 * The source-zone data of a repeating event with a named zone: its first source clock, its length in
 * minutes, and the offset from UTC (seconds) at that clock on each source day, as a list of
 * [first day, offset] changes. A repeat takes its time from the source zone, so the shown time
 * follows the daylight-saving changes of that zone. Null when the zone is unknown.
 */
function zonedSeries(start, endValue, localZone) {
    if (start.form !== "zone" || start.instantMs === null) return null;
    var hhmm = start.value.slice(9, 13);
    function offsetOn(dayN) {
        var wall = Times.keyOfDayNum(dayN).replace(/-/g, "") + "T" + hhmm + "00";
        return Math.round((Zones.clockMs(wall) - Zones.zoneInstant(wall, start.tzid, localZone)) / 1000);
    }
    var first = Times.dayNum(start.value.slice(0, 4) + "-" + start.value.slice(4, 6) + "-" + start.value.slice(6, 8));
    var offset = offsetOn(first);
    if (!isFinite(offset)) return null;
    var offsets = [[Times.keyOfDayNum(first), offset]];
    var before = first;
    for (var n = first + ZONE_SCAN_STEP; n <= first + ZONE_SCAN_DAYS; n += ZONE_SCAN_STEP) {
        var now = offsetOn(n);
        if (now === offset) { before = n; continue; }
        var low = before, high = n; // the offset changes on a day after `low`, up to `high`
        while (high - low > 1) {
            var middle = Math.floor((low + high) / 2);
            if (offsetOn(middle) === offset) low = middle; else high = middle;
        }
        offsets.push([Times.keyOfDayNum(high), now]);
        offset = now;
        before = n;
    }
    var length = endValue && endValue.instantMs !== null ? Math.round((endValue.instantMs - start.instantMs) / 60000) : null;
    return { date: Times.keyOfDayNum(first), time: start.value.slice(9, 11) + ":" + start.value.slice(11, 13),
        length: length !== null && length >= 0 ? length : null, offsets: offsets };
}

/** DTSTART, or DTEND for events and DUE for tasks. A date that cannot be read stays raw. */
function readDateProperty(read, p, localZone) {
    var isStart = p.name === "DTSTART";
    if (!isStart && p.name !== (read.isTodo ? "DUE" : "DTEND")) { read.item.raw.push(p.raw); return; }
    var value = parseDateProperty(p, localZone);
    if (isStart) read.start = value;
    else read.endValue = value;
    if (!value) read.item.raw.push(p.raw);
}

/** An old berri tag becomes a color. Any other category stays raw. */
function readCategory(read, p) {
    var oldColor = oldTagColors[p.value.trim().toLowerCase()];
    if (oldColor) read.legacyColor = oldColor; // old berri tag, replaced by X-BERRI-COLOR
    else read.item.raw.push(p.raw);
}

/** The first usable RRULE fills the repeat fields. A second or unusable one stays raw. */
function readRepeatRule(read, p, localZone) {
    var item = read.item;
    var repeatRule = { interval: 1, byDay: [], monthWeekday: null, until: null, count: null };
    var rule = parseRule(p.value, repeatRule, localZone);
    if (!rule.freq || item.repeat !== "none") { item.raw.push(p.raw); return; }
    item.repeat = rule.freq;
    item.interval = repeatRule.interval;
    item.byDay = repeatRule.byDay;
    item.monthWeekday = repeatRule.monthWeekday;
    item.until = repeatRule.until;
    read.sourceDates.until = repeatRule.untilSource || null;
    item.count = repeatRule.count;
    item.ruleRest = rule.rest.length ? rule.rest.join(";") : null; // rule parts berri ignores, written back as they were
}

function readExdates(read, p, localZone) {
    var sources = [];
    p.value.split(",").forEach(function (v) {
        var d = parseDateValue(v, p.params, localZone);
        if (d) { read.item.exdates.push(d.date); sources.push(d); }
    });
    read.sourceDates.exdates.push({ raw: p.raw, values: sources });
}

/** COMPLETED and NEEDS-ACTION are derived from the done dates when written. */
function readStatus(read, p) {
    var status = p.value.toUpperCase();
    if (status === "COMPLETED") read.sawDoneCompleted = true;
    else if (status !== "NEEDS-ACTION") read.item.status = status;
}

function readDoneDates(read, p) {
    p.value.split(",").forEach(function (v) {
        var d = parseDateValue(v);
        if (d) read.item.doneDates.push(d.date);
    });
}

/** Routes one property to the step that reads it. Unknown properties stay raw. */
function readProperty(read, p, localZone) {
    var item = read.item;
    switch (p.name) {
    case "UID": item.uid = p.value; break;
    case "DTSTAMP": item.stamp = p.value; break;
    case "SUMMARY": item.title = Text.unescapeText(p.value); break;
    case "DTSTART": case "DTEND": case "DUE": readDateProperty(read, p, localZone); break;
    case "CATEGORIES": readCategory(read, p); break;
    case "X-BERRI-COLOR": read.ownColor = p.value.trim(); break;
    case "RRULE": readRepeatRule(read, p, localZone); break;
    case "EXDATE": readExdates(read, p, localZone); break;
    case "STATUS": readStatus(read, p); break;
    case "X-BERRI-KIND": if (p.value.toLowerCase() === "reminder") item.kind = "reminder"; break;
    case "X-BERRI-DONE": readDoneDates(read, p); break;
    default: item.raw.push(p.raw);
    }
}

/** Sets date, time, end and end date from the start and end values. A lone end sets the date. */
function setItemDates(item, start, endValue, isTodo) {
    var first = start || endValue;
    if (first) {
        item.date = first.date;
        item.time = first.time;
    }
    if (!start || !endValue) return;
    if (start.time === null) {
        // All-day: VEVENT DTEND is exclusive, VTODO DUE is inclusive.
        var last = isTodo ? endValue.date : Items.addDays(endValue.date, -1);
        item.endDate = Times.dayNum(last) > Times.dayNum(start.date) ? last : null;
    } else if (endValue.time !== null) {
        if (endValue.time !== start.time || endValue.date !== start.date) item.end = endValue.time;
        if (endValue.date !== start.date) item.endDate = endValue.date;
    }
}

/** The one simple VALARM is taken over, the other children stay raw. */
function readChildren(item, children) {
    for (var c = 0; c < children.length; c++) {
        var child = children[c];
        var minutes = (child.name === "VALARM" && item.alarmMinutes === null) ? parseAlarm(child) : null;
        if (minutes !== null) item.alarmMinutes = minutes;
        else item.rawChildren.push(child.lines);
    }
}

function parseItem(node, localZone) {
    var isTodo = node.name === "VTODO";
    var item = Items.blankItem();
    if (isTodo) item.kind = "task";
    var read = { item: item, isTodo: isTodo, start: null, endValue: null, sawDoneCompleted: false,
        ownColor: null, legacyColor: null, sourceDates: { start: null, end: null, until: null, exdates: [] } };
    for (var i = 0; i < node.props.length; i++) readProperty(read, node.props[i], localZone);
    setItemDates(item, read.start, read.endValue, isTodo);
    read.sourceDates.start = read.start;
    read.sourceDates.end = read.endValue;
    item.sourceDates = read.sourceDates;
    if (item.repeat !== "none" && read.start) item.zoned = zonedSeries(read.start, read.endValue, localZone);
    if (item.uid === "") item.uid = Items.newUid();
    readChildren(item, node.children);
    if (read.sawDoneCompleted && item.repeat === "none" && item.date && item.doneDates.indexOf(item.date) < 0) item.doneDates.push(item.date);
    item.color = Items.cleanColor(read.ownColor) || read.legacyColor || "accent";
    return item;
}

/** The change one RECURRENCE-ID component makes to its series: { uid, entry }. Null for any other component. */
function changedOccurrence(node, localZone) {
    if (node.name !== "VEVENT" && node.name !== "VTODO") return null;
    var id = node.props.filter(function (p) { return p.name === "RECURRENCE-ID"; })[0];
    var uid = node.props.filter(function (p) { return p.name === "UID"; })[0];
    var from = id && uid ? parseDateValue(id.value, id.params, localZone) : null;
    if (!from) return null;
    var changed = parseItem(node, localZone);
    var cancelled = changed.status === "CANCELLED";
    var moved = !cancelled && changed.date !== null;
    return { uid: uid.value, entry: {
        from: from.date, cancelled: cancelled, title: !cancelled && changed.title !== "" ? changed.title : null,
        date: moved ? changed.date : null, time: moved ? changed.time : null,
        end: moved ? changed.end : null, endDate: moved ? changed.endDate : null } };
}

/** Parses the text of one .ics file. Never throws; garbage gives an empty calendar. A leading byte-order mark is ignored. */
function readCalendar(text, localZone) {
    var cal = { prodid: null, raw: [], rawComponents: [], items: [] };
    var roots = Text.parseComponents(Text.unfold((text || "").replace(/^\uFEFF/, "")));
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
        // The changed occurrences stay in rawComponents as they were; the series also gets a short form of each.
        for (var o = 0; o < root.children.length; o++) {
            var changed = changedOccurrence(root.children[o], localZone);
            var series = changed ? cal.items.filter(function (it) { return it.uid === changed.uid && it.repeat !== "none"; })[0] : null;
            if (series) series.changedOccurrences.push(changed.entry);
        }
    }
    return cal;
}

/**
 * A stored item from one stored link record. Malformed record fields take their defaults.
 * A record without a usable uid gets one made from its own fields, so every read gives the same uid.
 */
function expandCompactItem(record) {
    var item = Items.storedItem(record);
    if (item.uid === "") item.uid = "record-" + Items.shortHash([item.date, item.time, item.end, item.title, item.repeat].join("|"));
    return item;
}

function emptyCalendar() {
    return { prodid: null, raw: [], rawComponents: [], items: [] };
}
