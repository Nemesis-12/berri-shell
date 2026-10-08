.pragma library
.import "CalendarIdentity.js" as Identity
.import "CalendarFormat.js" as Format
.import "CalendarItems.js" as Items
.import "CalendarQueries.js" as Queries
.import "SavedCalendars.js" as SavedCalendars

/** Pure rules for the list of calendars that Calendar.qml keeps: names, files, saved entries and feed results. */

/** Day key for an optional date argument; anything that is not a date counts as "no date". */
function optionalKey(date) {
    if (!date) return null;
    var key = Items.toKey(date);
    return /^\d{4}-\d{2}-\d{2}$/.test(key) ? key : null;
}

/** A copy of the fields where date, endDate and until are day keys. */
function cleanDates(fields) {
    var out = {};
    for (var k in fields) {
        var v = fields[k];
        out[k] = (k === "date" || k === "endDate" || k === "until") && v && typeof v !== "string" ? Items.toKey(v) : v;
    }
    return out;
}

/** A calendar that is not loaded yet. The local calendar is always "accent"; others take a wanted or unused preset. */
function newMeta(dir, id, kind, name, file, color, usedColors) {
    return { id: id, kind: kind, name: name, color: kind === "local" ? "accent" : Queries.newCalendarColor(color, usedColors),
        hidden: false, url: "", file: file, updatedAt: 0, colorOverrides: ({}),
        path: dir + "/" + file, document: null, records: null, text: "", signature: "", error: "", convertError: "", refreshing: false, loaded: false, readFailed: false };
}

/** The calendar of one safe saved entry. */
function savedMeta(dir, s) {
    return { id: s.id, kind: s.kind, name: String(s.name || ""), color: Items.cleanColor(s.color) || "accent",
        hidden: !!s.hidden, url: s.kind === "link" ? String(s.url || "") : "", file: s.file, updatedAt: +s.updatedAt || 0,
        colorOverrides: s.kind === "link" ? Queries.pruneColorOverrides(s.colorOverrides, null) : ({}),
        path: dir + "/" + s.file, document: null, records: null, text: "", signature: "", error: "", convertError: "", refreshing: false, loaded: false, readFailed: false };
}

/**
 * The calendars from calendars.json: { calendars (by id), order }. The local calendar is always first.
 * An entry with a repeated id or an unsafe file name is skipped.
 */
function restoreCalendars(dir, values) {
    var saved = Array.isArray(values.calendars) ? values.calendars : [];
    var meta = {};
    var order = [];
    var local = newMeta(dir, Identity.LOCAL_ID, "local", Identity.LOCAL_ID, Identity.LOCAL_FILE, "", []);
    for (var i = 0; i < saved.length; i++) {
        var s = saved[i];
        if (!s || typeof s.id !== "string" || typeof s.file !== "string" || meta[s.id]) continue;
        if (s.id === Identity.LOCAL_ID) { local.color = Items.cleanColor(s.color) || "accent"; local.hidden = !!s.hidden; continue; }
        // Saved names become file paths: skip any entry that could reach outside the calendar folder.
        if (!SavedCalendars.isSafeEntry(s)) continue;
        meta[s.id] = savedMeta(dir, s);
        order.push(s.id);
    }
    meta[Identity.LOCAL_ID] = local;
    return { calendars: meta, order: [Identity.LOCAL_ID].concat(order) };
}

/** The entries written to calendars.json. */
function savedList(order, calendars) {
    return order.map(function (id) {
        var m = calendars[id];
        var out = { id: m.id, kind: m.kind, name: m.name, color: m.color, hidden: m.hidden, file: m.file, updatedAt: m.updatedAt };
        if (m.kind === "link") {
            out.url = m.url;
            if (Object.keys(m.colorOverrides).length > 0) out.colorOverrides = m.colorOverrides;
        }
        return out;
    });
}

/** Every item of every calendar (hidden ones too), in calendar order, each with its calendarId. */
function existingItems(order, calendars) {
    var out = [];
    for (var c = 0; c < order.length; c++) {
        var id = order[c];
        var doc = calendars[id].document;
        var items = doc ? doc.items : calendars[id].records || [];
        for (var i = 0; i < items.length; i++) {
            out.push(Items.projectedItem(doc ? items[i] : Format.expandCompactItem(items[i]), id, !doc));
        }
    }
    return out;
}

/** The id, or the id with -2, -3 ... when a calendar already has it. */
function uniqueId(calendars, id) {
    var unique = id;
    for (var n = 2; calendars[unique]; n++) unique = id + "-" + n;
    return unique;
}

/** The name of an imported file without folder or .ics, with unsafe characters replaced. */
function importStem(sourcePath) {
    var base = sourcePath.slice(sourcePath.lastIndexOf("/") + 1).replace(/[^A-Za-z0-9._ -]/g, "_");
    return base.replace(/\.ics$/i, "");
}

/** A safe file name in the calendar folder for an imported file; `taken` says whether a name is in use. */
function importFileName(sourcePath, taken) {
    var stem = importStem(sourcePath);
    var file = stem + ".ics";
    for (var n = 2; taken(file); n++) file = stem + "-" + n + ".ics";
    return file;
}

/** True when the file name belongs to berri.ics or to a calendar in the list (names compare without case). */
function fileTaken(order, calendars, file) {
    if (file.toLowerCase() === Identity.LOCAL_FILE) return true;
    return order.some(function (id) { return calendars[id].file.toLowerCase() === file.toLowerCase(); });
}

/** The id of the calendar that reads `path`. A link reads its records file (`recordPath`). "" when none. */
function idOfPath(order, calendars, path, recordPath) {
    for (var i = 0; i < order.length; i++) {
        var calendar = calendars[order[i]];
        if (calendar.path === path || calendar.kind === "link" && recordPath(calendar.path) === path) return order[i];
    }
    return "";
}

/** File calendars whose file is no longer listed. */
function missingFileIds(order, calendars, paths) {
    var present = {};
    for (var i = 0; i < paths.length; i++) present[paths[i]] = true;
    return order.filter(function (id) { return calendars[id].kind === "file" && !present[calendars[id].path]; });
}

/** Listed files that no calendar reads yet, as names inside the folder. berri.ics is the local calendar. */
function newFileNames(dir, paths, isKnownPath) {
    var names = [];
    for (var i = 0; i < paths.length; i++) {
        var file = paths[i].slice(dir.length + 1);
        if (file.toLowerCase() === Identity.LOCAL_FILE || isKnownPath(paths[i])) continue;
        names.push(file);
    }
    return names;
}

/** The error text of a finished download. Empty for success. */
function downloadError(code, exits, texts) {
    if (code === exits.parserMissing) return texts.parserMissing;
    if (code === exits.notCalendar) return "Not a calendar feed or parser failed";
    if (code === exits.saveFailed) return "Could not save calendar";
    return code !== 0 ? Queries.curlError(code) : "";
}

/** The records file content for a calendar, with its content signature. */
function recordsSignature(json) {
    return json.length + ":" + Items.shortHash(json);
}

/**
 * What a refresh of a link shows: the pruned color overrides, the new signature, and whether
 * nothing changed (same text, no error to clear, same overrides), so the cached months stay.
 */
function refreshResult(meta, doc, json) {
    var signature = recordsSignature(json);
    var overrides = Queries.pruneRecordColorOverrides(meta.colorOverrides, doc.records);
    var same = meta.signature === signature && !meta.error && !meta.convertError &&
        JSON.stringify(overrides) === JSON.stringify(meta.colorOverrides);
    return { signature: signature, overrides: overrides, same: same };
}

/** The parsed subscription records, or null when the text is not valid records. */
function parseRecords(json) {
    var parsed;
    try { parsed = JSON.parse(json); } catch (e) { return null; }
    return parsed && Array.isArray(parsed.records) ? parsed : null;
}

/** A copy of the color overrides of a link where one item has `color`; an empty color removes the override. */
function withItemColor(overrides, uid, color) {
    var out = {};
    for (var k in overrides) out[k] = overrides[k];
    if (color) out[uid] = color;
    else delete out[uid];
    return out;
}
