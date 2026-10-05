.pragma library
.import "Times.js" as Times

/**
 * Quick-add line parser. Ported rule for rule from the mock's parse() in
 * "Berri Calendar v2.dc.html" (5C). Pure: the caller passes the dates.
 *
 * parse(text, referenceDate, selectedDate, weekStart, clock24) returns
 *   { kind, allDay, title, date, time, end, repeat, byDay, color, tokens, matches, named }
 * kind is "event" | "task" | "reminder" (the store kinds). An event with no
 * time is all-day. date is "YYYY-MM-DD"; time and end are "HH:MM" or null.
 * tokens is the hint row: [{ text, kind }] with kind one of
 * "hint" | "kind" | "date" | "time" | "color" | "repeat" | "confirm" | "warn".
 *
 * matches has kind, date, time, end, color and repeat entries. Each is null or
 * { text, start, end }, with original input offsets and an exclusive end.
 * It reports the last accepted rule for each field, before all-day/task rules
 * clear times or ends. A time range supplies the same match for time and end.
 * Defaults have no match. "tonight" supplies both date and time unless a time
 * was already read. named has kind, date, time, color and repeat booleans for
 * form updates. named.time is false when all-day rules clear the time.
 * Callers can use matches.color.text.toLowerCase() for the entered color tag.
 *
 * referenceDate is "today" (words like "tomorrow" and weekday names count from
 * it). color is "#rrggbb" (lowercase) when the text has a #rgb or #rrggbb
 * word, else null (the caller keeps its current color). The hex word is cut
 * from the title. A word of three digits with no leading zero, like #123, is an
 * issue number: it stays in the title and gives no color. Preset names are not read from the text. selectedDate is the day used when the text names none. weekStart is
 * accepted for the caller's symmetry; the mock's rules do not use it.
 */

var WEEKDAY_NUMBER = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
var MONTH_NUMBER = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
var WEEKDAY_PATTERN = "(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:rs(?:day)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)";
var MONTH_PATTERN = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
var TIME_PATTERN = "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?";
var KIND_LABELS = { event: "Event", allday: "All-day", task: "Task", reminder: "Reminder" };
var REPEAT_LABELS = { daily: "Daily", weekly: "Weekly", monthly: "Monthly", yearly: "Yearly" };

function keyToDate(key) {
    var a = key.split("-").map(Number);
    return new Date(a[0], a[1] - 1, a[2]);
}

function addDays(key, n) {
    var d = keyToDate(key);
    d.setDate(d.getDate() + n);
    return Times.dayKey(d);
}

function daysBetween(a, b) {
    return Math.round((keyToDate(b) - keyToDate(a)) / 864e5);
}

// Month and day as the next such date. Null for 31 Feb and the like. A date more than 60 days back means next year.
function monthDay(month, day, today) {
    var year = keyToDate(today).getFullYear();
    var key = Times.dayKey(new Date(year, month, day));
    if (keyToDate(key).getMonth() !== month) return null;
    if (daysBetween(today, key) < -60) key = Times.dayKey(new Date(year + 1, month, day));
    return key;
}

// "Tue Sep 29".
function formatDay(key) {
    var d = keyToDate(key);
    return Times.weekdaysShort[d.getDay()] + " " + Times.monthsShort[d.getMonth()] + " " + d.getDate();
}

// Next date with that weekday, today included.
function nextWeekday(name, today) {
    var target = WEEKDAY_NUMBER[name.slice(0, 3).toLowerCase()];
    return addDays(today, (target - keyToDate(today).getDay() + 7) % 7);
}

// "HH:MM" from a clock reading, or null when the hour or minute is out of range.
function toTime(h, mi, ap) {
    h = +h;
    mi = +(mi || 0);
    if (ap) {
        ap = ap.toLowerCase();
        if (ap === "pm" && h < 12) h += 12;
        if (ap === "am" && h === 12) h = 0;
    }
    if (h > 23 || mi > 59) return null;
    return Times.pad(h) + ":" + Times.pad(mi);
}

var hasNoTime = function (o) { return !o.time; };
var hasNoDate = function (o) { return !o.date; };

// An issue number is three digits with no leading zero ("#123"). It is not a color and stays in the title.
var ISSUE_NUMBER_PATTERN = "[1-9][0-9]{2}";

/**
 * The rules, in the order they run. Each step cuts its words from the line and
 * sets fields on o. A later step sees the line without the words of the earlier ones.
 *   name    what the step reads
 *   fields  match fields the step reports
 *   when    optional: the step runs only if this returns true for o
 *   pattern what the step looks for
 *   accept  (m, o, today) sets o. Return false to leave the words in the line,
 *           or an array of field names to report instead of fields.
 */
var STEPS = [
    { name: "task", fields: ["kind"], pattern: /^\s*(?:task|todo)\b:?/i,
      accept: function (m, o) { o.type = "task"; } },
    { name: "reminder", fields: ["kind"], pattern: /^\s*remind(?:\s+me)?(?:\s+to)?\b:?/i,
      accept: function (m, o) { o.type = "reminder"; } },
    { name: "color", fields: ["color"], pattern: new RegExp("\\s#(?!" + ISSUE_NUMBER_PATTERN + "(?=\\s))([0-9a-f]{6}|[0-9a-f]{3})(?=\\s)", "i"),
      accept: function (m, o) {
        var h = m[1].toLowerCase();
        if (h.length === 3) h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2);
        o.color = "#" + h;
    } },
    { name: "all-day", fields: ["kind"], pattern: /\sall[\s-]?day\b/i,
      accept: function (m, o) { o.type = "allday"; } },
    { name: "every weekday", fields: ["repeat", "date"], pattern: new RegExp("\\severy\\s+" + WEEKDAY_PATTERN + "\\b", "i"),
      accept: function (m, o, today) {
        o.repeat = "weekly";
        o.date = nextWeekday(m[1], today);
        o.byDay = [WEEKDAY_NUMBER[m[1].slice(0, 3).toLowerCase()]];
    } },
    { name: "daily", fields: ["repeat"], pattern: /\s(?:every\s+day|daily)\b/i,
      accept: function (m, o) { o.repeat = "daily"; } },
    { name: "weekly", fields: ["repeat"], pattern: /\s(?:every\s+week|weekly)\b/i,
      accept: function (m, o) { o.repeat = "weekly"; } },
    { name: "monthly", fields: ["repeat"], pattern: /\s(?:every\s+month|monthly)\b/i,
      accept: function (m, o) { o.repeat = "monthly"; } },
    { name: "yearly", fields: ["repeat"], pattern: /\s(?:every\s+year|yearly|annually)\b/i,
      accept: function (m, o) { o.repeat = "yearly"; } },

    { name: "time range", fields: ["time", "end"],
      pattern: new RegExp("\\s(?:at\\s+|from\\s+)?" + TIME_PATTERN + "\\s*(?:-|\u2013|to)\\s*" + TIME_PATTERN + "(?=\\s)", "i"),
      accept: function (m, o) {
        var ap1 = m[3] || m[6];
        if (!(ap1 || m[2] || m[5])) return false;
        o.time = toTime(m[1], m[2], ap1);
        o.end = toTime(m[4], m[5], m[6]);
        if (!o.time) return false;
    } },
    { name: "am/pm time", fields: ["time"], when: hasNoTime, pattern: /\s(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?=\s)/i,
      accept: function (m, o) {
        o.time = toTime(m[1], m[2], m[3]);
        if (!o.time) return false;
    } },
    { name: "24-hour time", fields: ["time"], when: hasNoTime, pattern: /\s(?:at\s+)?(\d{1,2}):(\d{2})(?=\s)/,
      accept: function (m, o) {
        o.time = toTime(m[1], m[2]);
        if (!o.time) return false;
    } },
    { name: "noon", fields: ["time"], when: hasNoTime, pattern: /\s(?:at\s+)?noon\b/i,
      accept: function (m, o) { o.time = "12:00"; } },

    { name: "today or tonight", fields: ["date"], when: hasNoDate, pattern: /\s(?:on\s+)?(today|tonight)\b/i,
      accept: function (m, o, today) {
        o.date = today;
        if (/tonight/i.test(m[1]) && !o.time) {
            o.time = "20:00";
            return ["date", "time"];
        }
    } },
    { name: "tomorrow", fields: ["date"], when: hasNoDate, pattern: /\s(?:on\s+)?(tomorrow|tmrw|tmr)\b/i,
      accept: function (m, o, today) { o.date = addDays(today, 1); } },
    { name: "in N days", fields: ["date"], when: hasNoDate, pattern: /\sin\s+(\d{1,2})\s+days?\b/i,
      accept: function (m, o, today) { o.date = addDays(today, +m[1]); } },
    { name: "in N weeks", fields: ["date"], when: hasNoDate, pattern: /\sin\s+(\d{1,2})\s+weeks?\b/i,
      accept: function (m, o, today) { o.date = addDays(today, 7 * m[1]); } },
    { name: "next week", fields: ["date"], when: hasNoDate, pattern: /\snext\s+week\b/i,
      accept: function (m, o, today) { o.date = addDays(today, 7); } },
    { name: "month then day", fields: ["date"], when: hasNoDate,
      pattern: new RegExp("\\s(?:on\\s+)?" + MONTH_PATTERN + "\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b", "i"),
      accept: function (m, o, today) {
        o.date = monthDay(MONTH_NUMBER[m[1].slice(0, 3).toLowerCase()], +m[2], today);
        if (!o.date) return false;
    } },
    { name: "day then month", fields: ["date"], when: hasNoDate,
      pattern: new RegExp("\\s(?:on\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+" + MONTH_PATTERN + "\\b", "i"),
      accept: function (m, o, today) {
        o.date = monthDay(MONTH_NUMBER[m[2].slice(0, 3).toLowerCase()], +m[1], today);
        if (!o.date) return false;
    } },
    { name: "month/day", fields: ["date"], when: hasNoDate, pattern: /\s(?:on\s+)?(\d{1,2})\/(\d{1,2})\b/,
      accept: function (m, o, today) {
        o.date = monthDay(+m[1] - 1, +m[2], today);
        if (!o.date) return false;
    } },
    { name: "weekday", fields: ["date"], when: hasNoDate,
      pattern: new RegExp("\\s(?:on\\s+|next\\s+|this\\s+)?" + WEEKDAY_PATTERN + "\\b", "i"),
      accept: function (m, o, today) { o.date = nextWeekday(m[1], today); } }
];

function parse(text, referenceDate, selectedDate, weekStart, clock24) {
    var today = Times.dayKey(referenceDate);
    var s = " " + text + " ";
    var o = { type: null, date: null, time: null, end: null, color: null, repeat: "none", byDay: [] };

    var matches = { kind: null, date: null, time: null, end: null, color: null, repeat: null };
    var positions = [];
    for (var i = 0; i < s.length; i++) positions.push(i - 1);

    // Cuts accepted text and keeps its original range. A rule can return its fields.
    function take(re, fields, fn) {
        var m = s.match(re);
        if (!m) return;
        var accepted = fn(m);
        if (accepted === false) return;
        var first = m.index + m[0].search(/\S/);
        var last = m.index + m[0].replace(/\s+$/, "").length;
        var start = positions[first];
        var end = positions[last - 1] + 1;
        var match = { text: text.slice(start, end), start: start, end: end };
        var names = accepted || fields;
        for (var j = 0; j < names.length; j++) {
            if (names[j] !== "end" || o.end !== null) matches[names[j]] = match;
        }
        s = s.slice(0, m.index) + " " + s.slice(m.index + m[0].length);
        positions = positions.slice(0, m.index).concat([-1], positions.slice(m.index + m[0].length));
    }
    for (var r = 0; r < STEPS.length; r++) {
        var step = STEPS[r];
        if (step.when && !step.when(o)) continue;
        take(step.pattern, step.fields, function (m) { return step.accept(m, o, today); });
    }

    var title = s.replace(/\s+/g, " ").trim().replace(/\s+(on|at|from|by)$/i, "").replace(/^(on|at)\s+/i, "");
    if (!o.type) o.type = o.time ? "event" : "allday";
    if (o.type === "allday") { o.time = null; o.end = null; }
    if (o.type === "reminder" && !o.time) o.time = "09:00";
    if (o.type === "event" && o.time && !o.end) {
        o.end = Times.pad(Math.min(23, +o.time.slice(0, 2) + 1)) + ":" + o.time.slice(3);
    }
    if (o.type !== "event") o.end = null;

    var date = o.date || Times.dayKey(selectedDate);
    var result = {
        kind: o.type === "allday" ? "event" : o.type,
        allDay: o.type === "allday",
        title: title,
        date: date,
        time: o.time,
        end: o.end,
        repeat: o.repeat,
        byDay: o.byDay,
        color: o.color,
        tokens: [],
        matches: matches,
        named: {
            kind: matches.kind !== null,
            date: matches.date !== null,
            time: matches.time !== null && o.time !== null,
            color: matches.color !== null,
            repeat: matches.repeat !== null
        }
    };
    result.tokens = hintTokens(result, o.type, clock24);
    return result;
}

// Hint row for a parsed line, as the mock's tokens().
function hintTokens(p, type, clock24) {
    var t = [
        { text: KIND_LABELS[type], kind: "kind" },
        { text: formatDay(p.date), kind: "date" }
    ];
    if (p.time) t.push({ text: Times.clockText(p.time, clock24) + (p.end ? "\u2013" + Times.clockText(p.end, clock24) : ""), kind: "time" });
    if (p.color) t.push({ text: p.color, kind: "color" });
    if (p.repeat !== "none") t.push({ text: REPEAT_LABELS[p.repeat], kind: "repeat" });
    t.push(p.title ? { text: "\u21B2", kind: "confirm" } : { text: "needs a title", kind: "warn" });
    return t;
}

// Hint row for an empty line: where Enter adds, with an example.
function emptyHint(selectedDate) {
    return [{ text: "\u21B2 adds to " + formatDay(Times.dayKey(selectedDate)) + " \u00B7 fri 3pm #e93", kind: "hint" }];
}
