.pragma library
.import "CalendarIdentity.js" as Identity
.import "Times.js" as Times
.import "IcsText.js" as Text

/** Finds the occurrences of repeating items on given days, within a work limit. */

/** 0 = Sunday. */
function weekdayOf(n) {
    return (((n + 4) % 7) + 7) % 7;
}

function daysInMonth(year, month) {
    return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** Day number of the nth weekday (day 0 = Sunday) of a month. nth is 1 to 5, or -1 for the last. Null when the month has no such day. */
function weekdayInMonth(year, month, nth, day) {
    var first = Math.floor(Date.UTC(year, month - 1, 1) / 86400000);
    var last = first + daysInMonth(year, month) - 1;
    return weekdayInPeriod(first, last, nth, day);
}

/** Finds an ordinal weekday within a month or year, or null when it does not exist. */
function weekdayInPeriod(first, last, nth, day) {
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

/** Reads retained RRULE parts once for a series query. Their text stays unchanged on save. */
function retainedRuleParts(item) {
    var parts = {};
    (item.ruleRest || "").split(";").forEach(function (part) {
        var eq = part.indexOf("=");
        if (eq > 0) parts[part.slice(0, eq).toUpperCase()] = part.slice(eq + 1);
    });
    return parts;
}

/** Reads yearly weekday lists, including ordinals retained by both feed readers. */
function yearlyWeekdays(item, parts) {
    if (!parts.BYDAY) return item.byDay.map(function (day) { return { nth: 0, day: day }; });
    return parts.BYDAY.split(",").map(function (value) {
        var match = /^([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$/i.exec(value);
        return { nth: match && match[1] ? Number(match[1]) : 0,
            day: match ? Text.weekdays.indexOf(match[2].toUpperCase()) : -1 };
    });
}

/** The fixed numbers of a repeating series: its first day, step size, first week and month. */
function seriesOf(item) {
    var s = Times.dayNum(item.date);
    var parts = retainedRuleParts(item);
    var firstWeekday = Text.weekdays.indexOf((parts.WKST || "MO").toUpperCase());
    if (firstWeekday < 0) firstWeekday = 1;
    return {
        s: s,
        months: parts.BYMONTH ? parts.BYMONTH.split(",").map(Number) : [],
        monthDays: parts.BYMONTHDAY ? parts.BYMONTHDAY.split(",").map(Number) : [],
        positions: parts.BYSETPOS ? parts.BYSETPOS.split(",").map(Number) : [],
        yearlyWeekdays: item.repeat === "yearly" ? yearlyWeekdays(item, parts) : [],
        iv: Math.max(1, item.interval || 1),
        sy: +item.date.slice(0, 4), sm: +item.date.slice(5, 7), sd: +item.date.slice(8, 10),
        monthIndex: +item.date.slice(0, 4) * 12 + +item.date.slice(5, 7) - 1,
        weekStart: s - ((weekdayOf(s) - firstWeekday + 7) % 7),
        byDay: item.byDay.map(function (d) { return (d - firstWeekday + 7) % 7; }).sort(function (a, b) { return a - b; })
    };
}

/** The step to begin at, one step early, so a long gap before `fromN` costs no loop steps. */
function firstStep(item, fromN, c) {
    var fromDate = Times.keyOfDayNum(fromN);
    var fy = +fromDate.slice(0, 4), fm = +fromDate.slice(5, 7);
    var lowK;
    if (item.repeat === "daily") lowK = Math.floor((fromN - c.s) / c.iv);
    else if (item.repeat === "weekly") lowK = Math.floor((fromN - c.weekStart) / (7 * c.iv));
    else if (item.repeat === "monthly") lowK = Math.floor((fy * 12 + fm - 1 - c.monthIndex) / c.iv);
    else lowK = Math.floor((fy - c.sy) / c.iv);
    return Math.max(0, lowK - 1);
}

function dayOfUtc(year, month, day) {
    return Math.floor(Date.UTC(year, month - 1, day) / 86400000);
}

function weeklyStep(c, k) {
    if (!c.byDay.length) {
        var single = c.s + 7 * c.iv * k;
        return { base: single, list: [single] };
    }
    var base = c.weekStart + 7 * c.iv * k;
    return { base: base, list: c.byDay.map(function (o) { return base + o; }) };
}

/** Selects month days before positions and series bounds are applied. */
function monthStarts(item, c, y, mo) {
    var base = dayOfUtc(y, mo, 1);
    var last = daysInMonth(y, mo);
    if (c.months.length && c.months.indexOf(mo) < 0) return [];
    var ordinal = item.monthWeekday ? weekdayInMonth(y, mo, item.monthWeekday.nth, item.monthWeekday.day) : null;
    var first = item.repeat === "yearly" && !c.months.length ? dayOfUtc(y, 1, 1) : base;
    var end = item.repeat === "yearly" && !c.months.length ? dayOfUtc(y, 12, 31) : base + last - 1;
    var yearlyDays = c.yearlyWeekdays.map(function (weekday) {
        return { day: weekday.day, date: weekday.nth ? weekdayInPeriod(first, end, weekday.nth, weekday.day) : null,
            ordinal: weekday.nth !== 0 };
    });
    var days = [];
    for (var d = 1; d <= last; d++) {
        var n = base + d - 1;
        if (c.monthDays.length && c.monthDays.indexOf(d) < 0 && c.monthDays.indexOf(d - last - 1) < 0) continue;
        if (item.monthWeekday && n !== ordinal) continue;
        if (item.repeat === "yearly" && yearlyDays.length) {
            if (!yearlyDays.some(function (weekday) { return weekday.ordinal ? n === weekday.date : weekdayOf(n) === weekday.day; })) continue;
        } else if (item.byDay.length && item.byDay.indexOf(weekdayOf(n)) < 0) continue;
        if (!c.monthDays.length && !item.monthWeekday && !item.byDay.length && !yearlyDays.length && d !== c.sd) continue;
        days.push(n);
    }
    return days;
}

/** Selects positions in a complete month or year before series and query bounds. */
function selectedPositions(days, positions) {
    if (positions.length) days = days.filter(function (n, i) {
        return positions.indexOf(i + 1) >= 0 || positions.indexOf(i - days.length) >= 0;
    });
    return days;
}

/** Selects one complete month of a monthly series. */
function monthlyStep(item, c, k) {
    var idx = c.monthIndex + k * c.iv;
    var y = Math.floor(idx / 12), mo = idx % 12 + 1;
    return { base: dayOfUtc(y, mo, 1), list: selectedPositions(monthStarts(item, c, y, mo), c.positions) };
}

/** Selects one complete year of a yearly series. */
function yearlyStep(item, c, k) {
    var yr = c.sy + k * c.iv;
    var days = [];
    for (var mo = 1; mo <= 12; mo++) {
        if (!c.months.length && !c.monthDays.length && !c.yearlyWeekdays.length && mo !== c.sm) continue;
        days = days.concat(monthStarts(item, c, yr, mo));
    }
    return { base: dayOfUtc(yr, 1, 1), list: selectedPositions(days, c.positions) };
}

/** The base day and the start days of loop step k. Stops are decided by the caller from `base`. */
function stepStarts(item, c, k) {
    if (item.repeat === "daily") return { base: c.s + k * c.iv, list: [c.s + k * c.iv] };
    if (item.repeat === "weekly") return weeklyStep(c, k);
    if (item.repeat === "monthly") return monthlyStep(item, c, k);
    return yearlyStep(item, c, k);
}

/** Start days (as day numbers) of a repeating item that fall in [fromN, toN]. Stops early when `budget` has no steps left. */
function startDays(item, fromN, toN, budget) {
    var out = [];
    if (item.date === null) return out;
    var c = seriesOf(item);
    if (item.repeat === "none") {
        if (c.s >= fromN && c.s <= toN) out.push(c.s);
        return out;
    }
    var hi = item.until ? Math.min(toN, Times.dayNum(item.until)) : toN;
    var limit = item.count > 0 ? item.count : 0;
    // Daily and plain weekly series emit exactly one start per step, so a count can be skipped to as well.
    var oneEach = (item.repeat === "daily" && !item.byDay.length) || (item.repeat === "weekly" && !c.byDay.length);
    var lowK = (!limit || oneEach) ? firstStep(item, fromN, c) : 0;
    var emitted = limit && oneEach ? lowK : 0;
    for (var k = lowK; k < lowK + 200000; k++) {
        if (budget && !spend(budget, 1)) return out;
        var step = stepStarts(item, c, k);
        if (step.base > hi) break;
        for (var i = 0; i < step.list.length; i++) {
            var n = step.list[i];
            if (n < c.s) continue;
            if (item.repeat === "daily" && item.byDay.length && item.byDay.indexOf(weekdayOf(n)) < 0) continue;
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
        calendarId: item.calendarId || Identity.LOCAL_ID, readOnly: !!item.readOnly, hasOwnColor: !!item.hasOwnColor,
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

/** The repeat rule of a zoned series as it runs on source-zone days. The end bound allows two extra source days: the source and display zones can differ by 26 hours. */
function zonedRule(item) {
    return { date: item.zoned.date, repeat: item.repeat, interval: item.interval, byDay: item.byDay,
        monthWeekday: item.monthWeekday, ruleRest: item.ruleRest, count: item.count, until: item.until ? Times.addDays(item.until, 2) : null };
}

/** A copy of a zoned item whose date, time, end and endDate are the shown ones of the occurrence on source-zone day wallN. */
function zonedVariant(item, wallN) {
    var zoned = item.zoned;
    var wall = Times.keyOfDayNum(wallN);
    var startMs = Date.UTC(+wall.slice(0, 4), +wall.slice(5, 7) - 1, +wall.slice(8, 10), +zoned.time.slice(0, 2), +zoned.time.slice(3, 5), item.startSecond || 0) -
        zoneOffsetOn(zoned.offsets, wall) * 1000;
    var start = new Date(startMs);
    var shown = {};
    for (var k in item) shown[k] = item[k];
    shown.startMs = startMs;
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

/** Adds the shown days of one occurrence. Only days inside from..to are visited, so a very long event costs no more than a short one. */
function addShownDays(scan, variant, startN) {
    var span = spanDays(variant);
    var last = Math.min(span, scan.toN - startN);
    for (var d = Math.max(0, scan.fromN - startN); d <= last; d++) {
        if (!spend(scan.budget, 1)) return;
        scan.out.push(occurrenceOf(variant, startN, startN + d));
    }
}

/** Adds one series start unless it is excluded, cancelled or moved. A changed title shows. */
function addStart(scan, variant, startN) {
    var item = scan.item;
    var key = Times.keyOfDayNum(startN);
    if (item.untilMs !== null && item.untilMs !== undefined && variant.time !== null) {
        var startMs = variant.startMs !== undefined ? variant.startMs :
            new Date(+key.slice(0, 4), +key.slice(5, 7) - 1, +key.slice(8, 10),
                +variant.time.slice(0, 2), +variant.time.slice(3, 5), item.startSecond || 0).getTime();
        if (startMs > item.untilMs) return;
    }
    if (item.exdates.indexOf(key) >= 0) return;
    var change = changeFor(item, key);
    if (change && (change.cancelled || change.date !== null)) return;
    if (change && change.title !== null) {
        variant = shallowCopy(variant);
        variant.title = change.title;
    }
    addShownDays(scan, variant, startN);
}

/** A series with a named zone takes each start from the source zone clock. */
function addZonedStarts(scan) {
    var item = scan.item;
    var back = item.zoned.length ? Math.ceil(item.zoned.length / 1440) : 0;
    var walls = startDays(zonedRule(item), scan.fromN - back - 2, scan.toN + 2, scan.budget);
    for (var w = 0; w < walls.length && !scan.budget.limited; w++) {
        if (!spend(scan.budget, 1)) break;
        var shown = zonedVariant(item, walls[w]);
        var shownN = Times.dayNum(shown.date);
        if (shownN + spanDays(shown) >= scan.fromN && shownN <= scan.toN && !(item.until && shown.date > item.until))
            addStart(scan, shown, shownN);
    }
}

function addPlainStarts(scan) {
    var starts = startDays(scan.item, scan.fromN - spanDays(scan.item), scan.toN, scan.budget);
    for (var i = 0; i < starts.length && !scan.budget.limited; i++) addStart(scan, scan.item, starts[i]);
}

/** An occurrence the feed moved shows at its new day, but still belongs to the old occurrence date. */
function addMovedOccurrence(scan, change) {
    var item = scan.item;
    var moved = shallowCopy(item);
    moved.date = change.date;
    moved.time = change.time;
    moved.end = change.end;
    moved.endDate = change.endDate;
    if (change.title !== null) moved.title = change.title;
    var first = scan.out.length;
    addShownDays(scan, moved, Times.dayNum(change.date));
    for (var m = first; m < scan.out.length; m++) {
        scan.out[m].occurrenceDate = change.from;
        scan.out[m].repeat = item.repeat;
        scan.out[m].recurring = true;
        scan.out[m].done = item.doneDates.indexOf(change.from) >= 0;
    }
}

function addChangedOccurrences(scan) {
    var changes = scan.item.changedOccurrences || [];
    for (var c = 0; c < changes.length && !scan.budget.limited; c++) {
        var change = changes[c];
        if (!spend(scan.budget, 1)) break;
        if (change.cancelled || change.date === null || scan.item.exdates.indexOf(change.from) >= 0) continue;
        addMovedOccurrence(scan, change);
    }
}

function expandWithin(item, fromKey, toKey, budget) {
    var scan = { item: item, fromN: Times.dayNum(fromKey), toN: Times.dayNum(toKey), budget: budget, out: [] };
    if (item.zoned && item.repeat !== "none") addZonedStarts(scan);
    else addPlainStarts(scan);
    addChangedOccurrences(scan);
    return scan.out;
}

function shallowCopy(object) {
    var copy = {};
    for (var k in object) copy[k] = object[k];
    return copy;
}
