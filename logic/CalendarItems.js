.pragma library
.import "Times.js" as Times

/** Changes calendar items and finds their repeated dates and reminder times. */

var itemColors = ["accent", "blue", "green", "yellow", "red", "cyan", "magenta", "orange"];

/** 0 = Sunday. */
function weekdayOf(n) {
    return (((n + 4) % 7) + 7) % 7;
}

function daysInMonth(year, month) {
    return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** Accepts a "YYYY-MM-DD" string or a JS Date (local calendar day). */
function toKey(value) {
    if (typeof value === "string") return value.slice(0, 10);
    return Times.dayKey(value);
}

function addDays(key, days) {
    return Times.keyOfDayNum(Times.dayNum(key) + days);
}

/** A preset key or "#rrggbb" (lowercase, #rgb expanded), else null. */
function cleanColor(value) {
    if (typeof value !== "string") return null;
    var v = value.trim().toLowerCase();
    if (itemColors.indexOf(v) >= 0) return v;
    var m = v.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/);
    if (!m) return null;
    var h = m[1];
    if (h.length === 3) h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2);
    return "#" + h;
}

/** A calendar and its file UID as one string for QML signals and drag actions. */
function itemKey(calendarId, uid) {
    return JSON.stringify([calendarId, uid]);
}

function itemIdentity(key) {
    try {
        var pair = JSON.parse(key);
        if (Array.isArray(pair) && pair.length === 2 && typeof pair[0] === "string" && typeof pair[1] === "string")
            return { calendarId: pair[0], uid: pair[1] };
    } catch (e) { }
    return null;
}

/** Index of the item that `key` names in the list of calendar `calendarId`, or -1. Rows without a usable uid never match. */
function itemIndex(items, key, calendarId) {
    var identity = itemIdentity(key);
    if (!identity || identity.calendarId !== calendarId) return -1;
    for (var i = 0; i < items.length; i++)
        if (items[i] && items[i].uid === identity.uid) return i;
    return -1;
}

/** Short stable id text for a string (used for calendar ids and for link records without a uid). */
function shortHash(text) {
    var h = 5381;
    for (var i = 0; i < text.length; i++) h = ((h * 33) ^ text.charCodeAt(i)) >>> 0;
    return h.toString(36);
}

/**
 * Item forms, from the file to the screen:
 *   stored item     what a calendar file or a link record holds (storedItem).
 *   projected item  a copy with the calendar it sits in: calendarId, readOnly, hasOwnColor (projectedItem).
 *   occurrence      one shown day of a projected item (expand).
 *   shown item      a copy for QML whose uid is the item key and whose sourceUid is the file UID (shownItem).
 * A stored item is checked when it is built from a link record (expandCompactItem), a new item or an edit (makeItem, applyChanges).
 * Items read from a calendar file (parseItem) are built by the file reader and are not checked again, so a file round trip stays exact.
 * A shown item is checked when it goes out to a view.
 */

/** A copy of a stored item with the calendar it sits in. The stored item is not changed. */
function projectedItem(stored, calendarId, readOnly) {
    var copy = {};
    for (var k in stored) copy[k] = stored[k];
    copy.calendarId = typeof calendarId === "string" && calendarId !== "" ? calendarId : "berri";
    copy.readOnly = !!readOnly;
    copy.hasOwnColor = copy.readOnly ? false : stored.color !== "accent";
    return copy;
}

/** The view form of an item or occurrence. uid is the item key, sourceUid keeps the UID written in the file. */
function shownItem(item) {
    var copy = {};
    for (var k in item) copy[k] = item[k];
    var calendarId = typeof item.calendarId === "string" && item.calendarId !== "" ? item.calendarId : "berri";
    copy.sourceUid = typeof item.uid === "string" ? item.uid : "";
    copy.uid = itemKey(calendarId, copy.sourceUid);
    return copy;
}

function newUid() {
    return "berri-" + Math.random().toString(36).slice(2, 10) + Date.now().toString(36) + "@berri-shell";
}

function stampNow() {
    var d = new Date();
    return Times.pad(d.getUTCFullYear(), 4) + Times.pad(d.getUTCMonth() + 1) + Times.pad(d.getUTCDate()) + "T" +
        Times.pad(d.getUTCHours()) + Times.pad(d.getUTCMinutes()) + Times.pad(d.getUTCSeconds()) + "Z";
}

function normalize(item) {
    item.color = cleanColor(item.color) || "accent";
    if (item.kind !== "event") item.end = item.kind === "task" ? item.end : null;
    if (item.time === null) item.end = null;
    if (item.kind === "event" && item.time === null && item.endDate &&
        Times.dayNum(item.endDate) <= Times.dayNum(item.date)) item.endDate = null;
    if (item.kind === "reminder") {
        if (item.time === null) item.time = "09:00";
        if (item.alarmMinutes === null) item.alarmMinutes = 0;
    }
    if (item.repeat === "none") {
        item.interval = 1; item.byDay = []; item.until = null; item.count = null; item.exdates = []; item.ruleRest = null;
    }
    if (item.repeat !== "weekly") item.byDay = [];
    return item;
}

var KINDS = ["event", "task", "reminder"];
var REPEATS = ["none", "daily", "weekly", "monthly", "yearly"];

function isText(v) { return typeof v === "string"; }
function isDayKey(v) { return typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v); }
function isClock(v) { return typeof v === "string" && /^\d{2}:\d{2}$/.test(v); }
function isWhole(v, min) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= min; }
function orNull(check) { return function (v) { return v === null || check(v); }; }
function listOf(check) {
    return function (v) {
        if (v === null || v === undefined) return [];
        if (!Array.isArray(v)) return undefined;
        return v.filter(check);
    };
}

/**
 * How each stored field is checked. A check returns the clean value, or
 * undefined when the value is not usable. List fields keep only their usable
 * entries and treat null as an empty list.
 */
var fieldChecks = {
    uid: function (v) { return isText(v) && v !== "" ? v : undefined; },
    kind: function (v) { return KINDS.indexOf(v) >= 0 ? v : undefined; },
    title: function (v) { return isText(v) ? v : undefined; },
    date: function (v) { return v === null || isDayKey(v) ? v : undefined; },
    time: function (v) { return v === null || isClock(v) ? v : undefined; },
    end: function (v) { return v === null || isClock(v) ? v : undefined; },
    endDate: function (v) { return v === null || isDayKey(v) ? v : undefined; },
    color: function (v) { return cleanColor(v) || undefined; },
    repeat: function (v) { return REPEATS.indexOf(v) >= 0 ? v : undefined; },
    interval: function (v) { return isWhole(v, 1) ? v : undefined; },
    byDay: listOf(function (d) { return isWhole(d, 0) && d <= 6; }),
    until: function (v) { return v === null || isDayKey(v) ? v : undefined; },
    count: function (v) { return v === null || isWhole(v, 1) ? v : undefined; },
    exdates: listOf(isDayKey),
    doneDates: listOf(isDayKey),
    alarmMinutes: function (v) { return v === null || isWhole(v, 0) ? v : undefined; },
    status: function (v) { return v === null || isText(v) ? v : undefined; },
    stamp: function (v) { return v === null || isText(v) ? v : undefined; },
    ruleRest: function (v) { return v === null || isText(v) ? v : undefined; },
    raw: listOf(isText),
    rawChildren: listOf(function (c) { return Array.isArray(c); })
};

/** Copies the usable values of `fields` over `item`. Fields that fail their check keep the value already in `item`. */
function takeCheckedFields(item, fields) {
    for (var name in fieldChecks) {
        if (fields[name] === undefined) continue;
        var clean = fieldChecks[name](fields[name]);
        if (clean !== undefined) item[name] = clean;
    }
    return item;
}

/**
 * The stored form of an item, from a file, a link record or the edit form.
 * Fields that are missing or malformed get their default. The result is
 * the same for the same fields. A missing uid stays "": makeItem gives a new item its uid.
 * location (links) and sourceDates (imports) pass through. CalendarIcs.js describes the fields.
 */
function storedItem(fields) {
    var item = {
        uid: "", kind: "event", title: "",
        date: null, time: null, end: null, endDate: null,
        color: "accent", repeat: "none", interval: 1, byDay: [], until: null, count: null,
        exdates: [], doneDates: [], alarmMinutes: null, status: null, stamp: null, ruleRest: null,
        raw: [], rawChildren: []
    };
    takeCheckedFields(item, fields);
    if (fields.location !== undefined) item.location = fields.location;
    if (fields.sourceDates !== undefined) item.sourceDates = fields.sourceDates;
    return normalize(item);
}

/** A new item from the edit form: the stored form, with a new uid and a stamp of now when the fields give none. */
function makeItem(fields) {
    var item = storedItem(fields);
    if (item.uid === "") item.uid = newUid();
    if (item.stamp === null) item.stamp = stampNow();
    return item;
}

/** Returns a copy of the item with the usable changes applied. A malformed change keeps the old value. */
function applyChanges(item, changes) {
    var next = {};
    for (var k in item) next[k] = item[k];
    var allowed = {};
    for (var c in changes) {
        if (c === "uid" || c === "calendarId" || c === "readOnly" || c === "sourceUid" || c === "sourceDates" ||
            changes[c] === undefined) continue;
        allowed[c] = changes[c];
    }
    takeCheckedFields(next, allowed);
    for (var extra in allowed) if (!(extra in fieldChecks)) next[extra] = allowed[extra];
    if (allowed.repeat !== undefined && next.repeat !== item.repeat) {
        next.raw = next.raw.filter(function (l) { return !/^RRULE[;:]/i.test(l); });
        next.ruleRest = null;
        if (next.repeat === "none") next.exdates = [];
    }
    next.stamp = stampNow();
    return normalize(next);
}

function withDone(item, occurrenceDate, done) {
    var key = item.repeat === "none" ? item.date : occurrenceDate;
    if (key === null || key === undefined) return item;
    var list = item.doneDates.filter(function (d) { return d !== key; });
    if (done) list.push(key);
    list.sort();
    return applyChanges(item, { doneDates: list });
}

/** Deletes one occurrence of a recurring item (adds an EXDATE). Returns null when the item ends up gone. */
function withoutOccurrence(item, occurrenceDate) {
    if (item.repeat === "none") return null;
    var ex = item.exdates.filter(function (d) { return d !== occurrenceDate; });
    ex.push(occurrenceDate);
    ex.sort();
    var done = item.doneDates.filter(function (d) { return d !== occurrenceDate; });
    return applyChanges(item, { exdates: ex, doneDates: done });
}

/**
 * Moves one occurrence to another day (and optionally changes other fields, e.g. time for a snooze).
 * Returns { item, created }. Non-recurring: item is the moved item, created is null.
 * Recurring: item is the series without that occurrence, created is a new single item.
 */
function moveOccurrence(item, fromDate, toDate, changes) {
    var wasDone = item.doneDates.indexOf(item.repeat === "none" ? item.date : fromDate) >= 0;
    var span = item.endDate ? Times.dayNum(item.endDate) - Times.dayNum(item.date) : 0;
    var extra = {};
    for (var k in changes) extra[k] = changes[k];
    extra.date = toDate;
    extra.endDate = item.endDate ? addDays(toDate, span) : null;
    if (item.repeat === "none") {
        extra.doneDates = wasDone ? [toDate] : [];
        return { item: applyChanges(item, extra), created: null };
    }
    var single = applyChanges(item, extra);
    single.uid = newUid();
    single.repeat = "none";
    single.doneDates = wasDone ? [toDate] : [];
    single.raw = single.raw.filter(function (l) { return !/^RRULE[;:]/i.test(l); });
    single.exdates = [];
    return { item: withoutOccurrence(item, fromDate), created: normalize(single) };
}

/**
 * Where a snooze puts a reminder. amount is minutes or "1d". Past-due reminders
 * on today count from now, not from their old time.
 */
function snoozeTarget(time, dateKey, amount, nowKey, nowTime) {
    var t = time || "09:00";
    if (amount === "1d") return { date: addDays(dateKey, 1), time: t };
    var h = +t.slice(0, 2), m = +t.slice(3, 5);
    if (dateKey === nowKey && h * 60 + m < +nowTime.slice(0, 2) * 60 + +nowTime.slice(3, 5)) {
        h = +nowTime.slice(0, 2);
        m = +nowTime.slice(3, 5);
    }
    var mins = h * 60 + m + amount;
    var date = dateKey;
    while (mins >= 1440) { date = addDays(date, 1); mins -= 1440; }
    return { date: date, time: Times.pad(Math.floor(mins / 60)) + ":" + Times.pad(mins % 60) };
}

/** Start days (as day numbers) of a repeating item that fall in [fromN, toN]. */
function startDays(item, fromN, toN) {
    var out = [];
    if (item.date === null) return out;
    var s = Times.dayNum(item.date);
    if (item.repeat === "none") {
        if (s >= fromN && s <= toN) out.push(s);
        return out;
    }
    var hi = item.until ? Math.min(toN, Times.dayNum(item.until)) : toN;
    var iv = Math.max(1, item.interval || 1);
    var limit = item.count > 0 ? item.count : 0;
    var sy = +item.date.slice(0, 4), sm = +item.date.slice(5, 7), sd = +item.date.slice(8, 10);
    var monthIndex = sy * 12 + sm - 1;
    var weekStart = s - ((weekdayOf(s) + 6) % 7); // Monday of the first week
    var byDay = item.byDay.map(function (d) { return (d + 6) % 7; }).sort(function (a, b) { return a - b; });

    var lowK = 0;
    if (!limit) {
        var fromDate = Times.keyOfDayNum(fromN);
        var fy = +fromDate.slice(0, 4), fm = +fromDate.slice(5, 7);
        if (item.repeat === "daily") lowK = Math.floor((fromN - s) / iv);
        else if (item.repeat === "weekly") lowK = Math.floor((fromN - weekStart) / (7 * iv));
        else if (item.repeat === "monthly") lowK = Math.floor((fy * 12 + fm - 1 - monthIndex) / iv);
        else lowK = Math.floor((fy - sy) / iv);
        lowK = Math.max(0, lowK - 1);
    }

    var emitted = 0;
    for (var k = lowK; k < lowK + 200000; k++) {
        var base, list;
        if (item.repeat === "daily") { base = s + k * iv; list = [base]; }
        else if (item.repeat === "weekly") {
            base = (byDay.length ? weekStart : s) + 7 * iv * k;
            list = byDay.length ? byDay.map(function (o) { return base + o; }) : [base];
        } else if (item.repeat === "monthly") {
            var idx = monthIndex + k * iv;
            var y = Math.floor(idx / 12), mo = idx % 12 + 1;
            base = Math.floor(Date.UTC(y, mo - 1, 1) / 86400000);
            list = sd <= daysInMonth(y, mo) ? [base + sd - 1] : []; // no such day this month: skipped, as RFC 5545 says
        } else {
            var yr = sy + k * iv;
            base = Math.floor(Date.UTC(yr, 0, 1) / 86400000);
            list = sd <= daysInMonth(yr, sm) ? [Math.floor(Date.UTC(yr, sm - 1, sd) / 86400000)] : [];
        }
        if (base > hi) break;
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            if (n < s) continue;
            emitted++;
            if (limit && emitted > limit) return out;
            if (n > hi) return out;
            if (n >= fromN) out.push(n);
        }
    }
    return out;
}

function occurrenceOf(item, startN, dayN) {
    var start = Times.keyOfDayNum(startN);
    var spanDays = item.endDate ? Times.dayNum(item.endDate) - Times.dayNum(item.date) : 0;
    return {
        uid: item.uid, kind: item.kind, title: item.title, color: item.color,
        calendarId: item.calendarId || "berri", readOnly: !!item.readOnly, hasOwnColor: !!item.hasOwnColor,
        date: Times.keyOfDayNum(dayN), occurrenceDate: start,
        time: item.time, end: item.end,
        endDate: item.endDate ? Times.keyOfDayNum(startN + spanDays) : null,
        allDay: item.time === null,
        repeat: item.repeat, recurring: item.repeat !== "none",
        done: item.doneDates.indexOf(start) >= 0,
        alarmMinutes: item.alarmMinutes
    };
}

/** Occurrences of one item on the days from..to (inclusive keys). A multi-day item shows on every day it covers. */
function expand(item, fromKey, toKey) {
    var fromN = Times.dayNum(fromKey), toN = Times.dayNum(toKey);
    var span = item.endDate && item.time === null ? Times.dayNum(item.endDate) - Times.dayNum(item.date) : 0;
    var starts = startDays(item, fromN - span, toN);
    var out = [];
    for (var i = 0; i < starts.length; i++) {
        if (item.exdates.indexOf(Times.keyOfDayNum(starts[i])) >= 0) continue;
        for (var d = 0; d <= span; d++) {
            var day = starts[i] + d;
            if (day >= fromN && day <= toN) out.push(occurrenceOf(item, starts[i], day));
        }
    }
    return out;
}

/**
 * Reminder occurrences whose alert time (start minus alarmMinutes, local time)
 * lies in (fromMs, toMs], oldest first. Ticked-off ones are left out.
 * Result: [{ calendarId, uid, occurrenceDate, title, time, dueMs }].
 */
function dueBetween(items, fromMs, toMs) {
    var out = [];
    var fromKey = toKey(new Date(fromMs));
    var toDay = toKey(new Date(toMs));
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (item.kind !== "reminder" || item.time === null || item.date === null) continue;
        var alarm = item.alarmMinutes || 0;
        var list = expand(item, fromKey, addDays(toDay, Math.ceil(alarm / 1440) + 1));
        for (var j = 0; j < list.length; j++) {
            var occ = list[j];
            if (occ.done) continue;
            var dueMs = new Date(+occ.date.slice(0, 4), +occ.date.slice(5, 7) - 1, +occ.date.slice(8, 10),
                +occ.time.slice(0, 2), +occ.time.slice(3, 5)).getTime() - alarm * 60000;
            if (dueMs > fromMs && dueMs <= toMs)
                out.push({ calendarId: occ.calendarId, uid: occ.uid, occurrenceDate: occ.occurrenceDate,
                    title: occ.title, time: occ.time, dueMs: dueMs });
        }
    }
    out.sort(function (a, b) { return a.dueMs - b.dueMs; });
    return out;
}

/** Alert time (ms) of the first reminder after afterMs within horizonDays, or null. */
function nextDueMs(items, afterMs, horizonDays) {
    var list = dueBetween(items, afterMs, afterMs + horizonDays * 86400000);
    return list.length ? list[0].dueMs : null;
}

/** Sets every item of a list back to the default color ("accent" = no own color). Returns how many items changed. */
function clearItemColors(items) {
    var changed = 0;
    for (var i = 0; i < items.length; i++) {
        if (items[i].color === "accent") continue;
        items[i].color = "accent";
        changed++;
    }
    return changed;
}
