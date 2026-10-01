.pragma library
.import "QuickAddParser.js" as QuickAdd
.import "Times.js" as Times

// Reads the named parts once. Defaults do not count as named parts.
function parseLine(text, base, reference, clock24) {
    var selected = new Date(+base.date.slice(0, 4), +base.date.slice(5, 7) - 1, +base.date.slice(8, 10));
    var parsed = QuickAdd.parse(text, reference, selected, 1, clock24);
    return {
        parsed: parsed,
        type: parsed.allDay ? "allday" : parsed.kind,
        named: parsed.named,
        colorText: parsed.matches.color ? parsed.matches.color.text.toLowerCase() : ""
    };
}

// Typed parts fill untouched fields. Deleted parts restore the opening values.
function fromText(base, touched, draft, text, reference, clock24) {
    var line = parseLine(text, base, reference, clock24);
    var parsed = line.parsed;
    var named = line.named;
    var type = touched.type ? draft.type : (named.kind || named.time) ? line.type : base.type;
    return {
        line: line,
        fields: {
            raw: text,
            title: parsed.title,
            type: type,
            time: type === "allday" ? "" : touched.time ? draft.time : named.time ? parsed.time : (base.time || (type === "task" ? "" : "09:00")),
            end: type !== "event" ? "" : touched.end ? draft.end : (named.time && !touched.time) ? (parsed.end || base.end) : base.end,
            date: touched.date ? draft.date : named.date ? parsed.date : base.date,
            repeat: touched.repeat ? draft.repeat : named.repeat ? parsed.repeat : base.repeat,
            byDay: touched.repeat ? draft.byDay : named.repeat ? parsed.byDay : base.byDay,
            color: touched.color ? draft.color : named.color ? parsed.color : base.color
        }
    };
}

// Hints name only the typed parts that filled fields, using the draft's values.
function buildHint(line, touched, draft, clock24, readOnly) {
    if (readOnly || !line || draft.raw.trim() === "") return null;
    var named = line.named;
    var parts = [];
    if (named.kind && !touched.type) parts.push(QuickAdd.KIND_LABELS[draft.type]);
    if (named.date && !touched.date) parts.push(QuickAdd.formatDay(draft.date));
    if (named.time && !touched.time && draft.type !== "allday" && draft.time !== "") {
        var span = draft.end && !touched.end && draft.type === "event" ? "\u2013" + Times.clockText(draft.end, clock24) : "";
        parts.push(Times.clockText(draft.time, clock24) + span);
    }
    if (named.repeat && !touched.repeat) parts.push(draft.repeat.charAt(0).toUpperCase() + draft.repeat.slice(1));
    if (named.color && !touched.color) parts.push(line.colorText);
    if (parts.length === 0) return null;
    return { text: parts.join(" · "), swatch: named.color && !touched.color ? draft.color : "" };
}

// Maps form fields to saved fields. Moving an event keeps its day span.
function toStoredFields(draft, original) {
    var isEvent = draft.type === "event" || draft.type === "allday";
    var time = draft.type === "allday" ? null : (draft.time !== "" ? draft.time : (draft.type === "reminder" ? "09:00" : null));
    var endDate = null;
    if (isEvent && original && original.endDate) {
        endDate = Times.keyOfDayNum(Times.dayNum(original.endDate) + Times.dayNum(draft.date) - Times.dayNum(original.date));
    }
    return {
        kind: isEvent ? "event" : draft.type,
        title: draft.title.trim(),
        date: draft.date,
        time: time,
        end: draft.type === "event" && time !== null && draft.end !== "" ? draft.end : null,
        endDate: endDate,
        color: draft.color,
        repeat: draft.repeat,
        byDay: draft.byDay
    };
}

// Keeps the heading readable for an unknown imported item type.
function typeLabel(key, types) {
    var type = types.filter(function (choice) { return choice.key === key; })[0];
    return type ? type.label : "Item";
}

// Steps a YYYY-MM-DD day by whole days.
function stepDate(day, direction) {
    return Times.keyOfDayNum(Times.dayNum(day) + direction);
}

// Accepts only a full date that exists in the calendar.
function validDate(text) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
    var day = new Date(+text.slice(0, 4), +text.slice(5, 7) - 1, +text.slice(8, 10));
    return Times.dayKey(day) === text;
}

// Steps HH:MM by five minutes. An empty time starts at 09:00.
function stepTime(time, direction) {
    var minutes = time === "" ? 9 * 60 : Number(time.slice(0, 2)) * 60 + Number(time.slice(3, 5)) + direction * 5;
    minutes = (minutes + 1440) % 1440;
    return Times.pad(Math.floor(minutes / 60)) + ":" + Times.pad(minutes % 60);
}

// Accepts a full 24-hour time.
function validTime(text) {
    return /^([01]\d|2[0-3]):[0-5]\d$/.test(text);
}
