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

var addDays = Times.addDays;

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
        item.zoned = null; item.changedOccurrences = [];
    }
    if (item.repeat !== "weekly") item.byDay = [];
    if (item.repeat !== "monthly") item.monthWeekday = null;
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
    monthWeekday: function (v) {
        if (v === null) return v;
        if (!v || !isWhole(v.day, 0) || v.day > 6 || !isWhole(Math.abs(v.nth), 1) || Math.abs(v.nth) > 5) return undefined;
        return { nth: v.nth, day: v.day };
    },
    until: function (v) { return v === null || isDayKey(v) ? v : undefined; },
    count: function (v) { return v === null || isWhole(v, 1) ? v : undefined; },
    exdates: listOf(isDayKey),
    doneDates: listOf(isDayKey),
    alarmMinutes: function (v) { return v === null || isWhole(v, 0) ? v : undefined; },
    status: function (v) { return v === null || isText(v) ? v : undefined; },
    stamp: function (v) { return v === null || isText(v) ? v : undefined; },
    ruleRest: function (v) { return v === null || isText(v) ? v : undefined; },
    zoned: function (v) {
        if (v === null) return v;
        if (!v || !isDayKey(v.date) || !isClock(v.time) || !(v.length === null || isWhole(v.length, 0)) ||
            !Array.isArray(v.offsets) || v.offsets.length === 0) return undefined;
        var offsets = [];
        for (var i = 0; i < v.offsets.length; i++) {
            var o = v.offsets[i];
            if (!Array.isArray(o) || !isDayKey(o[0]) || !isWhole(Math.abs(o[1]), 0)) return undefined;
            offsets.push([o[0], o[1]]);
        }
        return { date: v.date, time: v.time, length: v.length, offsets: offsets };
    },
    changedOccurrences: listOf(function (c) {
        return !!c && isDayKey(c.from) && typeof c.cancelled === "boolean" && orNull(isText)(c.title) &&
            orNull(isDayKey)(c.date) && orNull(isClock)(c.time) && orNull(isClock)(c.end) && orNull(isDayKey)(c.endDate);
    }),
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
        color: "accent", repeat: "none", interval: 1, byDay: [], monthWeekday: null, until: null, count: null,
        exdates: [], doneDates: [], alarmMinutes: null, status: null, stamp: null, ruleRest: null,
        zoned: null, changedOccurrences: [],
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
    // The zone data describes the imported start; a new start or repeat makes it wrong.
    if (next.date !== item.date || next.time !== item.time || next.end !== item.end || next.repeat !== item.repeat) next.zoned = null;
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

/**
 * Where a reminder snooze puts it, counted from its alert time (start minus
 * alarmMinutes), or from now when the alert time is past. amount is minutes
 * or "1d". Returns { date, time, alarmMinutes }: a minute snooze clears the
 * alarm offset, a day snooze keeps it.
 */
function snoozeReminder(time, dateKey, alarmMinutes, amount, nowKey, nowTime) {
    var t = time || "09:00";
    var alarm = alarmMinutes || 0;
    if (amount === "1d") return { date: addDays(dateKey, 1), time: t, alarmMinutes: alarm };
    var start = Times.dayNum(dateKey) * 1440 + +t.slice(0, 2) * 60 + +t.slice(3, 5);
    var now = Times.dayNum(nowKey) * 1440 + +nowTime.slice(0, 2) * 60 + +nowTime.slice(3, 5);
    var at = Math.max(start - alarm, now) + amount;
    var day = Math.floor(at / 1440);
    return { date: addDays(dateKey, day - Times.dayNum(dateKey)), time: Times.pad(Math.floor(at % 1440 / 60)) + ":" + Times.pad(at % 60), alarmMinutes: 0 };
}

/** Day number of the nth weekday (day 0 = Sunday) of a month. nth is 1 to 5, or -1 for the last. Null when the month has no such day. */
function weekdayInMonth(year, month, nth, day) {
    var first = Math.floor(Date.UTC(year, month - 1, 1) / 86400000);
    var last = first + daysInMonth(year, month) - 1;
    var n = nth > 0 ? first + ((day - weekdayOf(first) + 7) % 7) + (nth - 1) * 7
        : last - ((weekdayOf(last) - day + 7) % 7) + (nth + 1) * 7;
    return n >= first && n <= last ? n : null;
}

/**
 * Work limits for one month query. A feed is outside input, so it can hold an event
 * that covers 8000 years or 60,000 repeating items. Each loop step and each shown
 * occurrence costs one step. One item may use `itemSteps`; one query may use `steps`
 * for all its items and `items` records. An item over its limit adds nothing, and the
 * query budget is marked `limited` so the caller knows the answer is not complete.
 * These numbers are a default for the maintainer to confirm. A normal month needs under
 * 2,000 steps.
 */
var workLimits = { steps: 10000, itemSteps: 3000, items: 2000 };

function newWorkBudget() {
    return { steps: workLimits.steps, limited: false };
}

/** Spends `n` steps. Returns false (and marks the budget limited) when they are gone. */
function spend(budget, n) {
    budget.steps -= n;
    if (budget.steps >= 0) return true;
    budget.limited = true;
    return false;
}

/** Start days (as day numbers) of a repeating item that fall in [fromN, toN]. Stops early when `budget` has no steps left. */
function startDays(item, fromN, toN, budget) {
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

    // Daily and plain weekly series emit exactly one start per step, so a count can be skipped to as well.
    var oneEach = item.repeat === "daily" || (item.repeat === "weekly" && !byDay.length);
    var lowK = 0;
    if (!limit || oneEach) {
        var fromDate = Times.keyOfDayNum(fromN);
        var fy = +fromDate.slice(0, 4), fm = +fromDate.slice(5, 7);
        if (item.repeat === "daily") lowK = Math.floor((fromN - s) / iv);
        else if (item.repeat === "weekly") lowK = Math.floor((fromN - weekStart) / (7 * iv));
        else if (item.repeat === "monthly") lowK = Math.floor((fy * 12 + fm - 1 - monthIndex) / iv);
        else lowK = Math.floor((fy - sy) / iv);
        lowK = Math.max(0, lowK - 1);
    }

    var emitted = limit && oneEach ? lowK : 0;
    for (var k = lowK; k < lowK + 200000; k++) {
        if (budget && !spend(budget, 1)) return out;
        var base, list;
        if (item.repeat === "daily") { base = s + k * iv; list = [base]; }
        else if (item.repeat === "weekly") {
            base = (byDay.length ? weekStart : s) + 7 * iv * k;
            list = byDay.length ? byDay.map(function (o) { return base + o; }) : [base];
        } else if (item.repeat === "monthly") {
            var idx = monthIndex + k * iv;
            var y = Math.floor(idx / 12), mo = idx % 12 + 1;
            base = Math.floor(Date.UTC(y, mo - 1, 1) / 86400000);
            if (item.monthWeekday) {
                var weekday = weekdayInMonth(y, mo, item.monthWeekday.nth, item.monthWeekday.day);
                list = weekday === null ? [] : [weekday];
            } else list = sd <= daysInMonth(y, mo) ? [base + sd - 1] : []; // no such day this month: skipped, as RFC 5545 says
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
    var lengthDays = item.endDate ? Times.dayNum(item.endDate) - Times.dayNum(item.date) : 0;
    return {
        uid: item.uid, kind: item.kind, title: item.title, color: item.color,
        calendarId: item.calendarId || "berri", readOnly: !!item.readOnly, hasOwnColor: !!item.hasOwnColor,
        date: Times.keyOfDayNum(dayN), occurrenceDate: start,
        time: item.time, end: item.end,
        endDate: item.endDate ? Times.keyOfDayNum(startN + lengthDays) : null,
        allDay: item.time === null,
        repeat: item.repeat, recurring: item.repeat !== "none",
        done: item.doneDates.indexOf(start) >= 0,
        alarmMinutes: item.alarmMinutes
    };
}

/** Offset (seconds east of UTC) of a zoned series on a source-zone day: the last table entry on or before that day. */
function zoneOffsetOn(offsets, key) {
    var offset = offsets[0][1];
    for (var i = 1; i < offsets.length && offsets[i][0] <= key; i++) offset = offsets[i][1];
    return offset;
}

function clockOfDate(date) {
    return Times.pad(date.getHours()) + ":" + Times.pad(date.getMinutes());
}

/** The repeat rule of a zoned series as it runs on source-zone days. The end bound gets one more day: a shown day can be a day earlier. */
function zonedRule(item) {
    return { date: item.zoned.date, repeat: item.repeat, interval: item.interval, byDay: item.byDay,
        monthWeekday: item.monthWeekday, count: item.count, until: item.until ? addDays(item.until, 1) : null };
}

/** A copy of a zoned item whose date, time, end and endDate are the shown ones of the occurrence on source-zone day wallN. */
function zonedVariant(item, wallN) {
    var zoned = item.zoned;
    var wall = Times.keyOfDayNum(wallN);
    var startMs = Date.UTC(+wall.slice(0, 4), +wall.slice(5, 7) - 1, +wall.slice(8, 10), +zoned.time.slice(0, 2), +zoned.time.slice(3, 5)) -
        zoneOffsetOn(zoned.offsets, wall) * 1000;
    var start = new Date(startMs);
    var shown = {};
    for (var k in item) shown[k] = item[k];
    shown.date = Times.dayKey(start);
    shown.time = clockOfDate(start);
    shown.end = null;
    shown.endDate = null;
    if (zoned.length) {
        var end = new Date(startMs + zoned.length * 60000);
        shown.end = clockOfDate(end);
        if (Times.dayKey(end) !== shown.date) shown.endDate = Times.dayKey(end);
    }
    return shown;
}

/** The change an imported feed made to the occurrence that starts on `key`, or null. */
function changeFor(item, key) {
    var changes = item.changedOccurrences || [];
    for (var i = 0; i < changes.length; i++) if (changes[i].from === key) return changes[i];
    return null;
}

/**
 * How many days after its start day an item still covers. An all-day item covers its endDate.
 * A timed event covers the day of its end, unless it ends exactly at 00:00 (that day is free).
 */
function spanDays(item) {
    if (!item.endDate) return 0;
    var days = Times.dayNum(item.endDate) - Times.dayNum(item.date);
    if (item.time === null) return days;
    if (item.kind !== "event" || days < 1) return 0;
    return item.end === "00:00" ? days - 1 : days;
}

/**
 * Occurrences of one item on the days from..to (inclusive keys). A multi-day item shows on every day it covers.
 * A cancelled item has none. An occurrence the feed cancelled has none. An occurrence the feed moved shows at its new time.
 */
function expand(item, fromKey, toKey, query) {
    if (item.status === "CANCELLED") return [];
    if (!query) query = newWorkBudget();
    if (query.steps <= 0) { query.limited = true; return []; }
    var budget = { steps: Math.min(workLimits.itemSteps, query.steps), limited: false };
    var allowed = budget.steps;
    var out = expandWithin(item, fromKey, toKey, budget);
    query.steps -= allowed - Math.max(budget.steps, 0);
    if (budget.limited) query.limited = true;
    return budget.limited ? [] : out;
}

function expandWithin(item, fromKey, toKey, budget) {
    var fromN = Times.dayNum(fromKey), toN = Times.dayNum(toKey);
    var out = [];
    function addShownDays(variant, startN) {
        // Only the days inside from..to are visited, so a very long event costs no more than a short one.
        var span = spanDays(variant);
        var last = Math.min(span, toN - startN);
        for (var d = Math.max(0, fromN - startN); d <= last; d++) {
            if (!spend(budget, 1)) return;
            out.push(occurrenceOf(variant, startN, startN + d));
        }
    }
    function addStart(variant, startN) {
        var key = Times.keyOfDayNum(startN);
        if (item.exdates.indexOf(key) >= 0) return;
        var change = changeFor(item, key);
        if (change && (change.cancelled || change.date !== null)) return;
        if (change && change.title !== null) {
            variant = shallowCopy(variant);
            variant.title = change.title;
        }
        addShownDays(variant, startN);
    }
    if (item.zoned && item.repeat !== "none") {
        var back = item.zoned.length ? Math.ceil(item.zoned.length / 1440) : 0;
        var walls = startDays(zonedRule(item), fromN - back - 2, toN + 2, budget);
        for (var w = 0; w < walls.length && !budget.limited; w++) {
            if (!spend(budget, 1)) break;
            var shown = zonedVariant(item, walls[w]);
            var shownN = Times.dayNum(shown.date);
            if (shownN + spanDays(shown) >= fromN && shownN <= toN && !(item.until && shown.date > item.until)) addStart(shown, shownN);
        }
    } else {
        var starts = startDays(item, fromN - spanDays(item), toN, budget);
        for (var i = 0; i < starts.length && !budget.limited; i++) addStart(item, starts[i]);
    }
    var changes = item.changedOccurrences || [];
    for (var c = 0; c < changes.length && !budget.limited; c++) {
        var change = changes[c];
        if (!spend(budget, 1)) break;
        if (change.cancelled || change.date === null || item.exdates.indexOf(change.from) >= 0) continue;
        var moved = shallowCopy(item);
        moved.date = change.date;
        moved.time = change.time;
        moved.end = change.end;
        moved.endDate = change.endDate;
        if (change.title !== null) moved.title = change.title;
        var first = out.length;
        addShownDays(moved, Times.dayNum(change.date));
        for (var m = first; m < out.length; m++) {
            out[m].occurrenceDate = change.from;
            out[m].repeat = item.repeat;
            out[m].recurring = true;
            out[m].done = item.doneDates.indexOf(change.from) >= 0;
        }
    }
    return out;
}

function shallowCopy(object) {
    var copy = {};
    for (var k in object) copy[k] = object[k];
    return copy;
}

/** An alarm offset above 4 weeks is ignored by reminder scans (an imported file can hold any number). */
var maxAlarmMinutes = 4 * 7 * 1440;

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
        if (alarm > maxAlarmMinutes) continue;
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
