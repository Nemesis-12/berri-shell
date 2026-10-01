.pragma library
.import "Times.js" as Times
.import "CalendarFormat.js" as Format
.import "CalendarItems.js" as Items

/** Joins calendar copies and answers day, month, color and duplicate queries. */

/** Day order (mock): all-day events first, then timed items by time, then items without a time; ties by title. */
function dayRank(o) {
    if (o.time !== null) return 0;
    return o.kind === "event" ? -1 : 1;
}

function compareOccurrences(a, b) {
    var byRank = dayRank(a) - dayRank(b);
    if (byRank !== 0) return byRank;
    if (a.time !== b.time && a.time !== null && b.time !== null) return a.time < b.time ? -1 : 1;
    if (a.title !== b.title) return a.title < b.title ? -1 : 1;
    return 0;
}

/** Title for the duplicate check: lower case, single spaces, no trailing score like " (2-1)". */
function titleKey(title) {
    return String(title || "").replace(/\s*\(\s*\d+\s*[-\u2013:]\s*\d+\s*\)\s*$/, "").toLowerCase().replace(/\s+/g, " ").trim();
}

/** Start of an entry as one text: day, time (or "all-day") and title. */
function startTitleKey(e, day) {
    return day + "|" + (e.time === null || e.time === undefined ? "all-day" : e.time) + "|" + titleKey(e.title);
}

/**
 * Groups entries (items or occurrences, in calendar order) that are the same event
 * in different calendars. keysOf(entry) gives [uidKey, startTitleKey]. Returns an
 * array of groups (arrays of entries, first-come order). An entry joins a group
 * only when the group has no entry of the same calendar yet.
 */
function duplicateGroups(entries, keysOf) {
    var groups = [];
    var byKey = {};
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i];
        var keys = keysOf(e);
        var group = null;
        for (var k = 0; k < keys.length && !group; k++) {
            var g = byKey[keys[k]];
            if (g && !g.some(function (m) { return m.calendarId === e.calendarId; })) group = g;
        }
        if (!group) { group = []; groups.push(group); }
        group.push(e);
        for (var j = 0; j < keys.length; j++) if (!byKey[keys[j]]) byKey[keys[j]] = group;
    }
    return groups;
}

/** The copy to show: the first one with its own color, else the first one. */
function keptCopy(group) {
    for (var i = 0; i < group.length; i++) if (group[i].hasOwnColor) return group[i];
    return group[0];
}

/**
 * Each duplicate group of entries once, in the order of the kept copies' groups.
 * `names` (optional, { calendarId: name }) gives the names for `alsoIn`; the id is used when missing.
 * Kept entries are copied only when they are a duplicate (alsoIn is set on the copy).
 */
function dropDuplicates(entries, keysOf, names) {
    var out = [];
    var groups = duplicateGroups(entries, keysOf);
    for (var g = 0; g < groups.length; g++) {
        var kept = keptCopy(groups[g]);
        var others = groups[g].filter(function (m) { return m !== kept; });
        kept.alsoInIds = others.map(function (m) { return m.calendarId; });
        kept.alsoIn = others.map(function (m) { return names && names[m.calendarId] ? names[m.calendarId] : m.calendarId; });
        out.push(kept);
    }
    return out;
}

/** Duplicate-free occurrences (fields alsoIn and alsoInIds are set on every one). */
function dropDuplicateOccurrences(list, names) {
    return dropDuplicates(list, function (o) {
        return ["u|" + o.uid + "|" + o.occurrenceDate + "|" + o.date, "t|" + startTitleKey(o, o.date) + "|" + o.occurrenceDate];
    }, names);
}

function itemKeys(it) {
    return ["u|" + it.uid + "|" + it.repeat, "t|" + startTitleKey(it, it.date) + "|" + it.repeat + "|" + (it.interval || 1)];
}

/** Duplicate-free items (for reminders). Same rule as for occurrences. */
function dropDuplicateItems(items) {
    return dropDuplicates(items, itemKeys, null);
}

/** How many items of `feedItems` already exist in `existingItems` (items with a calendarId). Duplicates inside the feed count as one each. */
function countDuplicates(feedItems, existingItems) {
    var seen = {};
    for (var i = 0; i < existingItems.length; i++) {
        var keys = itemKeys(existingItems[i]);
        for (var k = 0; k < keys.length; k++) seen[keys[k]] = true;
    }
    var count = 0;
    for (var f = 0; f < feedItems.length; f++) {
        var fk = itemKeys(feedItems[f]);
        if (seen[fk[0]] || seen[fk[1]]) count++;
    }
    return count;
}

/** { "YYYY-MM-DD": [Occurrence] } for days from..to. Shared events show once. */
function occurrencesByDay(items, fromKey, toKey, names) {
    var all = [];
    for (var i = 0; i < items.length; i++) {
        var list = Items.expand(items[i], fromKey, toKey);
        for (var j = 0; j < list.length; j++) all.push(list[j]);
    }
    var days = {};
    var shown = dropDuplicateOccurrences(all, names);
    for (var s = 0; s < shown.length; s++) {
        (days[shown[s].date] = days[shown[s].date] || []).push(shown[s]);
    }
    for (var key in days) days[key].sort(compareOccurrences);
    return days;
}

function itemsOn(items, dateKey) {
    return occurrencesByDay(items, dateKey, dateKey)[dateKey] || [];
}

/** Same as occurrencesByDay for the whole calendar month (month 1 to 12). */
function itemsInMonth(items, year, month, names) {
    var last = Items.daysInMonth(year, month);
    return occurrencesByDay(items, Times.pad(year, 4) + "-" + Times.pad(month) + "-01", Times.pad(year, 4) + "-" + Times.pad(month) + "-" + Times.pad(last), names);
}

/** Name of a parsed calendar (X-WR-CALNAME), or "". */
function calendarName(cal) {
    for (var i = 0; i < cal.raw.length; i++) {
        var m = cal.raw[i].match(/^X-WR-CALNAME[^:]*:(.*)$/i);
        if (m) return Format.unescapeText(m[1]).trim();
    }
    return "";
}

/** True when the text has a VCALENDAR block. */
function looksLikeCalendar(text) {
    return /^BEGIN:VCALENDAR\s*$/im.test(text || "");
}

/** "https://..." for an https:// or webcal:// link, else null. */
function feedUrl(url) {
    var u = String(url || "").trim();
    if (/^webcal:\/\//i.test(u)) u = "https://" + u.slice(9);
    return /^https:\/\/[^\s\/]+[^\s]*$/i.test(u) ? "https://" + u.slice(8) : null;
}

/** Host of a link, for example "holidays.example.org". */
function linkHost(url) {
    var m = String(url || "").match(/^[a-z]+:\/\/([^\/?#]+)/i);
    return m ? m[1].replace(/^.*@/, "") : "";
}

/** Short stable id text for a string (used for calendar ids). */
function shortHash(text) {
    var h = 5381;
    for (var i = 0; i < text.length; i++) h = ((h * 33) ^ text.charCodeAt(i)) >>> 0;
    return h.toString(36);
}

/** The first preset color that no calendar uses yet (used = list of colors); repeats when all are taken. */
function unusedColor(used) {
    for (var i = 0; i < Items.itemColors.length; i++)
        if (used.indexOf(Items.itemColors[i]) < 0) return Items.itemColors[i];
    return Items.itemColors[used.length % Items.itemColors.length];
}

/** The color for a new calendar: `wanted` (preset key or "#rrggbb") when valid, else the first unused preset. */
function newCalendarColor(wanted, used) {
    return Items.cleanColor(wanted) || unusedColor(used);
}

/**
 * Joins several calendars into one item list for the views.
 * calendars: [{ id, color, hidden, readOnly, items }]. Every stored item gets
 * calendarId and readOnly. The result holds copies of the items of calendars
 * that are not hidden. An item keeps its own color; an item with the default
 * color ("accent", not written to the file) takes the color of its calendar.
 * calendar.colorOverrides ({ uid: color }, links only) gives single items a
 * color of their own. hasOwnColor tells if the item has its own color.
 */
function mergeCalendars(calendars) {
    var out = [];
    for (var c = 0; c < calendars.length; c++) {
        var cal = calendars[c];
        for (var i = 0; i < cal.items.length; i++) {
            var item = cal.items[i];
            item.calendarId = cal.id;
            item.readOnly = !!cal.readOnly;
            item.hasOwnColor = cal.readOnly ? false : item.color !== "accent";
            if (cal.hidden) continue;
            var copy = {};
            for (var k in item) copy[k] = item[k];
            var own = cal.readOnly && cal.colorOverrides ? Items.cleanColor(cal.colorOverrides[item.uid]) : null;
            if (own) { copy.color = own; copy.hasOwnColor = true; }
            else if (item.color === "accent") copy.color = cal.color || "accent";
            out.push(copy);
        }
    }
    return out;
}

/** A copy of a stored link item with its color override applied (for the edit form). Other items are returned as they are. */
function withColorOverride(item, overrides) {
    var own = item.readOnly && overrides ? Items.cleanColor(overrides[item.uid]) : null;
    if (!own) return item;
    var copy = {};
    for (var k in item) copy[k] = item[k];
    copy.color = own;
    copy.hasOwnColor = true;
    return copy;
}

/** The overrides ({ uid: color }) whose uid is still in items (null items keeps every uid). Bad colors are dropped too. Returns a new object. */
function pruneColorOverrides(overrides, items) {
    var live = {};
    for (var i = 0; items && i < items.length; i++) live[items[i].uid] = true;
    var out = {};
    for (var uid in overrides || {}) {
        var color = Items.cleanColor(overrides[uid]);
        if ((!items || live[uid]) && color) out[uid] = color;
    }
    return out;
}

function pruneRecordColorOverrides(overrides, records) {
    var live = {};
    for (var i = 0; i < records.length; i++) live[Format.expandCompactItem(records[i]).uid] = true;
    var out = {};
    for (var uid in overrides || {}) {
        var color = Items.cleanColor(overrides[uid]);
        if (live[uid] && color) out[uid] = color;
    }
    return out;
}

/** Short message for a curl exit code. */
function curlError(code) {
    switch (code) {
    case 3: case 1: case 2: return "Not a valid link";
    case 6: case 7: return "Cannot reach the host";
    case 22: return "The server refused the request";
    case 28: return "Timed out";
    case 35: case 51: case 58: case 60: case 77: case 83: return "Secure connection failed";
    case 63: return "The feed is too large";
    default: return "Download failed";
    }
}

/** Builds the calendar rows, month inputs and reminders from the same calendars. */
function projectCalendars(calendars) {
    var rows = [];
    var names = {};
    var itemPaths = {};
    var lists = [];
    for (var c = 0; c < calendars.length; c++) {
        var calendar = calendars[c];
        var items = calendar.document ? calendar.document.items : [];
        for (var i = 0; i < items.length; i++) itemPaths[Items.itemKey(calendar.id, items[i].uid)] = calendar.path;
        names[calendar.id] = calendar.name;
        lists.push({ id: calendar.id, color: calendar.color, hidden: calendar.hidden,
            readOnly: calendar.kind === "link", colorOverrides: calendar.colorOverrides, items: items });
        rows.push({ id: calendar.id, name: calendar.name, kind: calendar.kind, color: calendar.color,
            hidden: calendar.hidden, itemCount: items.length,
            source: calendar.kind === "link" ? linkHost(calendar.url) : calendar.kind === "file" ? calendar.file : "",
            updatedAt: calendar.updatedAt, readOnly: calendar.kind === "link", error: calendar.error || "" });
    }
    var shownItems = mergeCalendars(lists);
    return { calendars: rows, items: shownItems, names: names, itemPaths: itemPaths,
        reminders: dropDuplicateItems(shownItems.filter(function (item) { return !item.readOnly; })) };
}

/** Keep feed records in the projection. Create feed items only for a requested month. */
function projectStoredCalendars(calendars) {
    var rows = [], names = {}, local = [], sources = [];
    for (var c = 0; c < calendars.length; c++) {
        var cal = calendars[c];
        var records = cal.records || [];
        var items = cal.document ? cal.document.items : [];
        names[cal.id] = cal.name;
        rows.push({ id: cal.id, name: cal.name, kind: cal.kind, color: cal.color,
            hidden: cal.hidden, itemCount: cal.kind === "link" ? records.length : items.length,
            source: cal.kind === "link" ? linkHost(cal.url) : cal.kind === "file" ? cal.file : "",
            updatedAt: cal.updatedAt, readOnly: cal.kind === "link", error: cal.error || "" });
        if (cal.kind === "link") {
            if (!cal.hidden) sources.push({ id: cal.id, color: cal.color,
                colorOverrides: cal.colorOverrides, records: records });
        } else {
            var shown = mergeCalendars([{ id: cal.id, color: cal.color, hidden: cal.hidden,
                readOnly: false, items: items }]);
            for (var i = 0; i < shown.length; i++) local.push(shown[i]);
            if (!cal.hidden) sources.push({ items: shown });
        }
    }
    return { calendars: rows, sources: sources, names: names,
        reminders: dropDuplicateItems(local.filter(function (item) { return item.kind === "reminder"; })) };
}

function storedItemsInMonth(projection, year, month) {
    var first = Times.pad(year, 4) + "-" + Times.pad(month) + "-01";
    var last = Times.pad(year, 4) + "-" + Times.pad(month) + "-" + Times.pad(Items.daysInMonth(year, month));
    var shown = [];
    for (var f = 0; f < projection.sources.length; f++) {
        var feed = projection.sources[f];
        if (feed.items) {
            for (var j = 0; j < feed.items.length; j++) shown.push(feed.items[j]);
            continue;
        }
        var records = feed.records;
        for (var i = 0; i < records.length; i++) {
            var r = records[i];
            if (r.slice(0, 10) > last) break;
            var item = Format.expandCompactItem(r);
            if (item.repeat === "none" && (item.endDate || item.date) < first) continue;
            if (item.repeat !== "none" && item.until && item.until < first) continue;
            item.calendarId = feed.id;
            item.readOnly = true;
            var own = Items.cleanColor(feed.colorOverrides && feed.colorOverrides[item.uid]);
            item.hasOwnColor = !!own;
            if (own) item.color = own;
            else if (item.color === "accent") item.color = feed.color || "accent";
            shown.push(item);
        }
    }
    return itemsInMonth(shown, year, month, projection.names);
}
