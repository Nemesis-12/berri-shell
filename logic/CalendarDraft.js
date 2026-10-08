.pragma library
.import "QuickAddParser.js" as QuickAdd
.import "Times.js" as Times

// Reads the named parts once. Defaults do not count as named parts.
function parseLine(text, base, reference, clock24) {
    var selected = new Date(+base.date.slice(0, 4), +base.date.slice(5, 7) - 1, +base.date.slice(8, 10));
    var parsed = QuickAdd.parse(text, reference, selected, clock24);
    return {
        parsed: parsed,
        type: parsed.allDay ? "allday" : parsed.kind,
        named: parsed.named,
        colorText: parsed.matches.color ? parsed.matches.color.text.toLowerCase() : ""
    };
}

// Field priority: a field the user touched wins, then a part typed in the line, then the opening value.
function chooseField(isTouched, isTyped, draftValue, typedValue, openingValue) {
    if (isTouched) return draftValue;
    if (isTyped) return typedValue;
    return openingValue;
}

// The start clock: a new task has no time, any other type starts at 09:00 unless the form opened with one.
function timeField(type, touched, draft, named, parsed, base) {
    if (type === "allday") return "";
    var openingTime = base.time || (type === "task" ? "" : "09:00");
    return chooseField(touched.time, named.time, draft.time, parsed.time, openingTime);
}

// The end clock: events follow a typed time range, a task keeps its due time until a time is typed.
function endField(type, touched, draft, named, parsed, base) {
    if (type !== "event" && type !== "task") return "";
    if (touched.end) return draft.end;
    var typedTime = named.time && !touched.time;
    if (!typedTime) return base.end;
    return type === "task" ? "" : (parsed.end || base.end);
}

// Typed parts fill untouched fields. Deleted parts restore the opening values.
function fromText(base, touched, draft, text, reference, clock24) {
    var line = parseLine(text, base, reference, clock24);
    var parsed = line.parsed;
    var named = line.named;
    var type = chooseField(touched.type, named.kind || named.time, draft.type, line.type, base.type);
    return {
        line: line,
        fields: {
            raw: text,
            title: parsed.title,
            type: type,
            time: timeField(type, touched, draft, named, parsed, base),
            end: endField(type, touched, draft, named, parsed, base),
            date: chooseField(touched.date, named.date, draft.date, parsed.date, base.date),
            repeat: chooseField(touched.repeat, named.repeat, draft.repeat, parsed.repeat, base.repeat),
            byDay: chooseField(touched.repeat, named.repeat, draft.byDay, parsed.byDay, base.byDay),
            color: chooseField(touched.color, named.color, draft.color, parsed.color, base.color)
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

// The saved start clock: all-day items have none, a reminder without a time falls back to 09:00.
function storedTime(draft) {
    if (draft.type === "allday") return null;
    if (draft.time !== "") return draft.time;
    return draft.type === "reminder" ? "09:00" : null;
}

// Maps form fields to saved fields. Moving an item keeps its day span.
// opening is the draft the form opened with. A field that still has its opening value keeps the
// stored value: an inherited color stays inherited. A stored end is always after the start.
function toStoredFields(draft, original, opening) {
    var isEvent = draft.type === "event" || draft.type === "allday";
    var hasSpan = isEvent || draft.type === "task";
    var time = storedTime(draft);
    var endDate = null;
    if (hasSpan && original && original.endDate) {
        endDate = Times.keyOfDayNum(Times.dayNum(original.endDate) + Times.dayNum(draft.date) - Times.dayNum(original.date));
    }
    var end = hasSpan && draft.type !== "allday" && time !== null && draft.end !== "" ? draft.end : null;
    if (end !== null && !(opening && draft.end === opening.end && endDate !== null)) {
        // A new end counts on the start day, or on the next day when it is not later than the start.
        endDate = null;
        if (end < time) endDate = Times.keyOfDayNum(Times.dayNum(draft.date) + 1);
        else if (end === time) end = null;
    }
    var unchangedColor = original && opening && draft.color === opening.color;
    return {
        kind: isEvent ? "event" : draft.type,
        title: draft.title.trim(),
        date: draft.date,
        time: time,
        end: end,
        endDate: endDate,
        color: unchangedColor ? original.color : draft.color,
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
