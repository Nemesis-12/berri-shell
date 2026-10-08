.pragma library
.import "CalendarIdentity.js" as Identity
.import "Times.js" as Times
.import "CalendarRepeat.js" as Repeat

/** Changes calendar items and finds their repeated dates and reminder times. */

/*
 * iCalendar (RFC 5545) subset used by berri's calendar. Pure functions, no QML.
 * Calendar.qml imports CalendarItems.js, CalendarFormat.js, CalendarQueries.js and CalendarMonths.js directly.
 *
 * Calendar shape:  { prodid, raw: [line], rawComponents: [[line]], items: [Item] }
 *
 * Item shape (all dates "YYYY-MM-DD", all times "HH:MM", local display time):
 *   uid, kind ("event" | "task" | "reminder"), title,
 *   date, time (null = all-day / no time), end (end time, events only),
 *   endDate (last day of a multi-day all-day event, else null),
 *   color (preset key "accent" | "blue" | "green" | "yellow" | "red" | "cyan" | "magenta" | "orange",
 *   or a custom "#rrggbb"; stored as X-BERRI-COLOR, "accent" is not written),
 *   repeat ("none" | "daily" | "weekly" | "monthly" | "yearly"), interval,
 *   byDay (weekly only, 0 = Sunday), monthWeekday (monthly only: { nth, day }, nth 1 to 5 or -1 for the last,
 *   day 0 = Sunday; from BYDAY=2TU), until, count,
 *   exdates (skipped occurrence dates), doneDates (occurrence dates ticked off),
 *   alarmMinutes (VALARM minutes before start, null = none), status, stamp,
 *   ruleRest (RRULE parts berri ignores, written back unchanged),
 *   zoned (repeating event with a named time zone: { date, time, length, offsets }, the first source clock,
 *   the length in minutes and the [first day, UTC offset in seconds] changes of that zone, so each
 *   occurrence follows the daylight-saving changes of the zone; null otherwise),
 *   changedOccurrences (RECURRENCE-ID components of a repeating event: { from, cancelled, title, date, time, end, endDate },
 *   from = the day the occurrence had, date null = not moved; the component also stays in rawComponents),
 *   raw (unknown property lines, kept as is), rawChildren (unknown nested components),
 *   sourceDates (imported DTSTART, DTEND/DUE, UNTIL and EXDATE source forms).
 *   This is the stored item. CalendarItems.js checks it when it is built (storedItem).
 *   A projected item is a copy with calendarId, readOnly and hasOwnColor (projectedItem).
 *   A shown item is a copy for QML with a pair key in uid and the file UID in sourceUid (shownItem).
 *
 * Occurrence shape (what day and month queries return):
 *   uid, kind, title, color, date (the day shown), occurrenceDate (start day of
 *   this occurrence, use it for setDone/remove/move), time, end, endDate,
 *   allDay, repeat, recurring, done, alarmMinutes, calendarId, readOnly,
 *   hasOwnColor, alsoIn (names of the other calendars that hold the same
 *   event, [] when none), alsoInIds (their ids).
 *   (calendarId, readOnly and hasOwnColor come from projectedItem.)
 *   Subscription detail items also include location from LOCATION.
 *
 * Duplicates: an event in several calendars shows once. Two entries of
 * DIFFERENT calendars are the same event when the uid is the same, or when
 * start (day and time) and title are the same (see titleKey). Entries of one
 * calendar are never merged. The kept copy is the one of the calendar that
 * comes first, unless another copy has its own color.
 *
 * Old berri files stored a tag in CATEGORIES (personal, work, health, home).
 * It is read as a color when X-BERRI-COLOR is missing and is not written back.
 * CATEGORIES from other apps stay as raw lines.
 *
 * Month numbers are 1 to 12 everywhere.
 * Known limits: unknown TZIDs keep their source clock for display until edited.
 * A zoned series follows its zone for ten years from its first day.
 * A moved occurrence without DTEND has no end time. Deleting a moved occurrence of an editable calendar
 * leaves its RECURRENCE-ID component in the file.
 * BYMONTHDAY, BYSETPOS, a BYDAY list with week numbers and other rule parts stay raw but are ignored.
 * A cancelled item (STATUS:CANCELLED) has no occurrences, also in an editable calendar.
 */

var itemColors = ["accent", "blue", "green", "yellow", "red", "cyan", "magenta", "orange"];

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
    copy.calendarId = typeof calendarId === "string" && calendarId !== "" ? calendarId : Identity.LOCAL_ID;
    copy.readOnly = !!readOnly;
    copy.hasOwnColor = copy.readOnly ? false : stored.color !== "accent";
    return copy;
}

/** The view form of an item or occurrence. uid is the item key, sourceUid keeps the UID written in the file. */
function shownItem(item) {
    var copy = {};
    for (var k in item) copy[k] = item[k];
    var calendarId = typeof item.calendarId === "string" && item.calendarId !== "" ? item.calendarId : Identity.LOCAL_ID;
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
 * The one factory of stored items: every field with its default. storedItem (link records, new items)
 * and the file reader (CalendarFormat.js parseItem) both start from it, so a new field is added here only.
 */
function blankItem() {
    return {
        uid: "", kind: "event", title: "",
        date: null, time: null, end: null, endDate: null,
        color: "accent", repeat: "none", interval: 1, byDay: [], monthWeekday: null, until: null, count: null,
        exdates: [], doneDates: [], alarmMinutes: null, status: null, stamp: null, ruleRest: null,
        zoned: null, changedOccurrences: [],
        raw: [], rawChildren: []
    };
}

/**
 * The stored form of an item, from a file, a link record or the edit form.
 * Fields that are missing or malformed get their default. The result is
 * the same for the same fields. A missing uid stays "": makeItem gives a new item its uid.
 * location (links) and sourceDates (imports) pass through. The comment at the top of this file describes the fields.
 */
function storedItem(fields) {
    var item = blankItem();
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
        var list = Repeat.expand(item, fromKey, addDays(toDay, Math.ceil(alarm / 1440) + 1));
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
