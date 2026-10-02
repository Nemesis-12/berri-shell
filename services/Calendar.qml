pragma Singleton
import QtQuick
import Quickshell
import "../logic/CalendarIcs.js" as Ics
import "../logic/CalendarSave.js" as Save
import "../logic/Times.js" as Times
import qs.common
import qs.notifications

/**
 * berri's calendars. Three kinds: "local" (berri.ics, always there), "file"
 * (an .ics file in ~/.local/share/berri-shell/calendar/, editable) and "link"
 * (a subscribed https:// or webcal:// feed, read-only, cached in
 * calendar/subscriptions/ and refreshed every 30 minutes). The folder is
 * watched: .ics files added or removed while berri runs are picked up.
 * Name, color, hidden and link data are kept in ~/.local/state/berri-shell/calendars.json.
 * Answers day and month queries and saves each change at once (atomic write).
 * New items go to berri.ics. The file format and the item shape are described
 * at the top of CalendarIcs.js.
 *
 * Views read Calendar.itemsOn(date) or Calendar.itemsInMonth(year, month) inside
 * a binding. Both read `revision`, so the binding runs again after every change.
 * Up to three months are cached. Item edits keep unchanged months; imports and
 * calendar-wide settings clear them. Do not edit the arrays.
 * The same event in several calendars shows once (see CalendarIcs.js): the copy
 * of the calendar added first, or the copy with its own color. It has `alsoIn`
 * and `alsoInIds`.
 * View uid values encode [calendarId, file UID]. Pass them unchanged to actions.
 * sourceUid holds the original UID. Stored items and files keep the original UID.
 * Dates are "YYYY-MM-DD" strings or JS Dates. Months are 1 to 12.
 */
Singleton {
    id: root

    /** How many calendar views are visible now (see WhileVisible.qml). The folder is scanned when the first one opens. */
    property alias viewers: files.viewers

    readonly property string dir: (Quickshell.env("HOME") || "") + "/.local/share/berri-shell/calendar"
    readonly property string defaultPath: dir + "/berri.ics"

    /** Goes up by one on every change (own edit or outside change). */
    property int revision: 0
    /** True when every file has been read once. */
    property bool ready: false

    /**
     * Every calendar: { id, name, kind ("local" | "file" | "link"), color (preset key or "#rrggbb"),
     * hidden, itemCount, source (link host or file name), updatedAt (ms, 0 = never), readOnly (links), error ("" or text) }.
     */
    readonly property var calendars: { void root.revision; return _months.projection.calendars; }
    /** Short text of the last failed importFile, "" after a good one. */
    property string lastError: ""
    /** An installation error shown in the Calendar source view. */
    property string parserError: ""
    readonly property string parserMissingText: "Calendar parser is missing. Build tools/feed-to-records"
    readonly property string convertErrorText: "Could not read the saved calendar file"
    readonly property string recordsErrorText: "Could not read subscription records"
    /** How many items of the last importFile were already in other calendars (0 after a failed import). */
    property int lastImportDuplicates: 0

    /**
     * A link was downloaded and read (nothing was saved). eventCount counts events and tasks.
     * duplicateCount: how many of them are already in the added calendars (same uid, or same start and title).
     */
    signal linkChecked(string url, bool ok, string name, int eventCount, string error, int duplicateCount)
    /** Subscribe finished. requestId identifies the call; id is the calendar id or empty on error. */
    signal subscribed(string url, string id, string error, int requestId)
    /** A calendar edit could not be saved and was undone. */
    signal saveFailed(string message)
    /** True while a Calendar tab shows `saveFailed` messages. The tab sets it. When false, the notifier shows them as a desktop notification. */
    property bool saveErrorShown: false

    // ---- queries

    /** Occurrences on one day, in day order (all-day first, then by time). */
    function itemsOn(date): var {
        var key = Ics.toKey(date);
        var month = itemsInMonth(+key.slice(0, 4), +key.slice(5, 7));
        return month[key] || [];
    }

    /** { "YYYY-MM-DD": [occurrence] } for one month. Each occurrence has a `color` (a preset key or "#rrggbb"), `hasOwnColor`, `calendarId`, `readOnly`, `alsoIn` (names of the calendars with a duplicate) and `alsoInIds`. Hidden calendars give nothing. */
    function itemsInMonth(year: int, month: int): var {
        void root.revision;
        return Ics.cachedItemsInMonth(_months, year, month);
    }

    /** The selected item for the detail form, or null. Editable items keep their full document fields. */
    function getItem(uid: string): var {
        void root.revision;
        var found = _locate(uid, false);
        if (!found) return null;
        return Ics.withItemIdentity(Ics.withColorOverride(_storedItem(found), found.meta.colorOverrides));
    }

    /** Reads the selected stored item and adds link details when needed. */
    function _storedItem(found: var): var {
        if (found.doc) return found.doc.items[found.index];
        var item = Ics.expandCompactItem(found.meta.records[found.index]);
        item.calendarId = found.meta.id;
        item.readOnly = true;
        return item;
    }

    /**
     * Gives one item its own color: a preset key or "#rrggbb"; null or "" clears it.
     * Works for every item. Local and file items keep it in the file (X-BERRI-COLOR).
     * Link items are read-only, so their color is kept in calendars.json and
     * survives a refresh. Returns false for an unknown item or a bad color.
     */
    function setItemColor(uid: string, color): bool {
        var found = _locate(uid, false);
        if (!found) return false;
        var clear = color === null || color === undefined || color === "";
        var clean = clear ? "" : Ics.cleanColor(color);
        if (!clear && !clean) return false;
        var item = _storedItem(found);
        if (!item.readOnly) return update(uid, { color: clean || "accent" });
        var meta = _calendars[item.calendarId];
        if (!meta) return false;
        var overrides = {};
        for (var k in meta.colorOverrides) overrides[k] = meta.colorOverrides[k];
        if (clean) overrides[item.uid] = clean;
        else delete overrides[item.uid];
        meta.colorOverrides = overrides;
        _saveState();
        _rebuildItem(meta, [item.uid]);
        return true;
    }

    // ---- changes. Each one saves the file and bumps revision.

    /** Adds an item to berri.ics, or to the file calendar in `calendarId` (fields as in CalendarIcs.js, at least date; `color` is a preset key or "#rrggbb", default "accent"). Returns true when the item is saved. */
    function add(fields: var): bool {
        var path = defaultPath;
        var target = fields.calendarId ? _calendars[fields.calendarId] : null;
        if (fields.calendarId && (!target || target.kind === "link")) return false;
        if (target) path = dir + "/" + target.file;
        var calendar = target || _calendars.berri;
        var doc = calendar.document || Ics.emptyCalendar();
        var item = Ics.makeItem(_cleanDates(fields));
        doc.items.push(item);
        calendar.document = doc;
        return _commit(path, [item.uid]);
    }

    /** Changes fields of the whole item (all occurrences of a repeating one). */
    function update(uid: string, changes: var): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        found.doc.items[found.index] = Ics.applyChanges(found.doc.items[found.index], _cleanDates(changes));
        return _commit(found.path, [found.doc.items[found.index].uid]);
    }

    /** Deletes an item, or only one occurrence when occurrenceDate is given for a repeating item. */
    function remove(uid: string, occurrenceDate): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        var item = found.doc.items[found.index];
        var day = _optionalKey(occurrenceDate);
        var kept = day ? Ics.withoutOccurrence(item, day) : null;
        if (kept) found.doc.items[found.index] = kept;
        else found.doc.items.splice(found.index, 1);
        return _commit(found.path, [item.uid]);
    }

    /** Ticks an item off. For a repeating item only that occurrence (occurrenceDate). */
    function setDone(uid: string, done: bool, occurrenceDate): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        var item = found.doc.items[found.index];
        found.doc.items[found.index] = Ics.withDone(item, _optionalKey(occurrenceDate) || item.date, done);
        return _commit(found.path, [item.uid]);
    }

    /**
     * Moves one occurrence to another day. A repeating item keeps its series
     * (minus that day) and gets a new single item on the new day. Optional
     * changes (for example { time: "18:00" }) apply to the moved item.
     */
    function move(uid: string, fromDate, toDate, changes: var): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        var moved = Ics.moveOccurrence(found.doc.items[found.index], Ics.toKey(fromDate), Ics.toKey(toDate), _cleanDates(changes || {}));
        found.doc.items[found.index] = moved.item;
        if (moved.created) found.doc.items.push(moved.created);
        return _commit(found.path, moved.created ? [moved.item.uid, moved.created.uid] : [moved.item.uid]);
    }

    /**
     * Pushes a reminder later. amount is minutes or "1d". Minutes count from
     * the alert time (start minus alarm). The moved item then alerts at its start.
     */
    function snooze(uid: string, occurrenceDate, amount): bool {
        var item = getItem(uid);
        if (!item || item.readOnly) return false;
        var now = new Date();
        var nowTime = Times.pad(now.getHours()) + ":" + Times.pad(now.getMinutes());
        var time = item.time;
        var changes = {};
        if (amount !== "1d" && item.alarmMinutes > 0 && time) {
            var early = Math.max(0, +time.slice(0, 2) * 60 + +time.slice(3, 5) - item.alarmMinutes);
            time = Times.pad(Math.floor(early / 60)) + ":" + Times.pad(early % 60);
            changes.alarmMinutes = 0;
        }
        var to = Ics.snoozeTarget(time, Ics.toKey(occurrenceDate), amount, Ics.toKey(now), nowTime);
        changes.time = to.time;
        return move(uid, occurrenceDate, to.date, changes);
    }

    /** Items that can alert: from calendars that are not hidden, links left out, duplicates once. Used by ReminderNotifier. Do not edit the array. */
    function allItems(): var {
        void root.revision;
        return _months.projection.reminders;
    }

    // ---- calendars

    /**
     * Copies an .ics file into the calendar folder as a new file calendar.
     * Returns its id (the existing id when the same content is already there),
     * or "" and sets `lastError`. Optional `color` (preset key or "#rrggbb") is
     * the color of a new calendar; default: the next unused preset.
     */
    function importFile(path: string, color): string {
        lastError = "";
        lastImportDuplicates = 0;
        var from = String(path).replace(/^file:\/\//, "");
        if (!/\.ics$/i.test(from)) return _fail("Not an .ics file");
        var text = files.readNow(from);
        if (text === null) return _fail("Cannot read the file");
        if (!Ics.looksLikeCalendar(text)) return _fail("Not a calendar file");
        for (var i = 0; i < _order.length; i++) {
            var other = _calendars[_order[i]];
            if (other.kind === "file" && other.text === text) return other.id;
        }
        var base = from.slice(from.lastIndexOf("/") + 1).replace(/[^A-Za-z0-9._ -]/g, "_");
        var stem = base.replace(/\.ics$/i, "");
        var file = stem + ".ics";
        for (var n = 2; _fileTaken(file); n++) file = stem + "-" + n + ".ics";
        var doc = Ics.readCalendar(text, _localZone);
        var duplicates = Ics.countDuplicates(doc.items, _existingItems());
        var dest = dir + "/" + file;
        var written = _write(dest, text, "", "Could not import calendar");
        if (!written.saved) { lastError = written.error; return ""; }
        var meta = _addCalendar("f-" + Ics.shortHash(file), "file", Ics.calendarName(doc) || stem, file, "", color);
        meta.document = doc;
        meta.text = text;
        meta.signature = text.length + ":" + Ics.shortHash(text);
        meta.loaded = true;
        _finishAdd();
        lastImportDuplicates = duplicates;
        return meta.id;
    }

    /** Downloads a link and reports what is in it. Nothing is saved. Result: `linkChecked`. */
    function checkLink(url: string): void {
        var https = Ics.feedUrl(url);
        if (!https) { Qt.callLater(function () { root.linkChecked(url, false, "", 0, "Use an https:// or webcal:// link", 0); }); return; }
        _download("check", url, https, "");
    }

    /** Returns the request id. The subscribed result carries the same id. */
    function subscribe(url: string, color): int {
        var requestId = ++_nextSubscription;
        var https = Ics.feedUrl(url);
        if (!https) {
            Qt.callLater(function () { root.subscribed(url, "", "Use an https:// or webcal:// link", requestId); });
            return requestId;
        }
        var id = "l-" + Ics.shortHash(https);
        if (_calendars[id]) {
            Qt.callLater(function () { root.subscribed(url, id, "", requestId); });
            return requestId;
        }
        _download("subscribe", url, https, id, color, requestId);
        return requestId;
    }

    /** Downloads a link calendar again now. A failure keeps the old items and sets `error`. */
    function refresh(id: string): void {
        var meta = _calendars[id];
        if (!meta || meta.kind !== "link" || meta.refreshing) return;
        meta.refreshing = true;
        _download("refresh", meta.url, Ics.feedUrl(meta.url) || meta.url, id);
    }

    /** Removes a file or link calendar and its file. The local calendar stays. */
    function removeCalendar(id: string): bool {
        var meta = _calendars[id];
        if (!meta || meta.kind === "local") return false;
        var path = dir + "/" + meta.file;
        delete _calendars[id];
        _order = _order.filter(function (o) { return o !== id; });
        files.removeFile(path);
        _finishAdd();
        return true;
    }

    function setCalendarColor(id: string, color: string): void {
        var clean = Ics.cleanColor(color);
        if (!_calendars[id] || !clean || _calendars[id].color === clean) return;
        _calendars[id].color = clean;
        _saveState();
        _rebuild();
    }

    /**
     * The preset a new calendar gets by default: the first preset that no
     * calendar uses (berri counts, so "accent" is taken when berri uses it).
     */
    function nextCalendarColor(): string {
        return Ics.newCalendarColor("", _usedColors());
    }

    /**
     * Sets the calendar color and removes every own color of its items, so all
     * items show the calendar color. Link: drops its color overrides. File: clears
     * X-BERRI-COLOR in the file. The local berri calendar is not allowed (false).
     * One save and one revision step. Returns false for an unknown id or a bad color.
     */
    function applyColorToCalendar(id: string, color: string): bool {
        var meta = _calendars[id];
        var clean = Ics.cleanColor(color);
        if (!meta || meta.kind === "local" || !clean) return false;
        var previousColor = meta.color;
        meta.color = clean;
        var path = dir + "/" + meta.file;
        var doc = meta.document;
        var fileChanged = false;
        if (meta.kind === "link") meta.colorOverrides = ({});
        else if (doc) fileChanged = Ics.clearItemColors(doc.items) > 0;
        if (fileChanged && !_commit(path)) {
            meta.color = previousColor;
            _rebuild();
            return false;
        }
        _saveState();
        if (!fileChanged) _rebuild();
        return true;
    }

    function setCalendarHidden(id: string, hidden: bool): void {
        if (!_calendars[id] || _calendars[id].hidden === hidden) return;
        _calendars[id].hidden = hidden;
        _saveState();
        _rebuild();
    }

    // ---- storage

    // Editable calendars keep documents and text; links keep compact records.
    property var _calendars: ({})
    property var _order: []
    property var _months: Ics.createMonthCache([])
    property bool _stateRead: false
    property int _nextSubscription: 0

    /** Day key for an optional date argument; anything that is not a date counts as "no date". */
    function _optionalKey(date): var {
        if (!date) return null;
        var key = Ics.toKey(date);
        return /^\d{4}-\d{2}-\d{2}$/.test(key) ? key : null;
    }

    function _cleanDates(fields: var): var {
        var out = {};
        for (var k in fields) {
            var v = fields[k];
            out[k] = (k === "date" || k === "endDate" || k === "until") && v && typeof v !== "string" ? Ics.toKey(v) : v;
        }
        return out;
    }

    /** Every item of every calendar (hidden ones too), in calendar order, each with its calendarId. */
    function _existingItems(): var {
        var out = [];
        for (var c = 0; c < _order.length; c++) {
            var id = _order[c];
            var meta = _calendars[id];
            var doc = meta.document;
            var items = doc ? doc.items : meta.records || [];
            for (var i = 0; i < items.length; i++) {
                var copy = {};
                var item = doc ? items[i] : Ics.expandCompactItem(items[i]);
                for (var k in item) copy[k] = item[k];
                copy.calendarId = id;
                out.push(copy);
            }
        }
        return out;
    }

    function _fail(message: string): string {
        lastError = message;
        return "";
    }

    /** The item and its file, or null. Items of link calendars are found only for reading. */
    function _locate(uid: string, forEdit: bool): var {
        var identity = Ics.itemIdentity(uid);
        var meta = identity ? _calendars[identity.calendarId] : null;
        if (!meta || forEdit && meta.kind === "link") return null;
        var doc = meta.document;
        var items = doc ? doc.items : meta.records || [];
        var index = items.findIndex(function (item) { return item.uid === identity.uid; });
        return index < 0 ? null : { path: meta.path, doc: doc, meta: meta, index: index };
    }

    function _idOfPath(path: string): string {
        for (var i = 0; i < _order.length; i++)
            if (_calendars[_order[i]].path === path ||
                _calendars[_order[i]].kind === "link" && files.recordPath(_calendars[_order[i]].path) === path) return _order[i];
        return "";
    }

    function _fileTaken(file: string): bool {
        if (file.toLowerCase() === "berri.ics") return true;
        for (var i = 0; i < _order.length; i++)
            if (_calendars[_order[i]].file.toLowerCase() === file.toLowerCase()) return true;
        return false;
    }

    function _usedColors(): var {
        return _order.map(function (o) { return _calendars[o].color; });
    }

    function _newMeta(id: string, kind: string, name: string, file: string, color): var {
        return { id: id, kind: kind, name: name, color: kind === "local" ? "accent" : Ics.newCalendarColor(color, _usedColors()),
            hidden: false, url: "", file: file, updatedAt: 0, colorOverrides: ({}),
            path: dir + "/" + file, document: null, records: null, text: "", signature: "", error: "", convertError: "", refreshing: false, loaded: false };
    }

    function _addCalendar(id: string, kind: string, name: string, file: string, url: string, color): var {
        var unique = id;
        for (var n = 2; _calendars[unique]; n++) unique = id + "-" + n;
        var meta = _newMeta(unique, kind, name, file, color);
        meta.url = url;
        meta.updatedAt = kind === "local" ? 0 : Date.now();
        _calendars[unique] = meta;
        _order = _order.concat([unique]);
        return meta;
    }

    // Saves state, adjusts the FileViews to the calendar list and rebuilds.
    function _finishAdd(): void {
        _syncPaths();
        _saveState();
        _rebuild();
    }

    // Replace every derived list together before notifying the views.
    function _rebuild(): void {
        _months = Ics.createMonthCache(_order.map(function (id) { return _calendars[id]; }));
        revision++;
    }

    // Reproject one calendar and keep months whose edited occurrences did not change.
    function _rebuildItem(calendar: var, uids: var): void {
        Ics.editMonthCache(_months, calendar, uids);
        revision++;
    }

    // Converts an IANA zone clock to an instant with the system zone database.
    function _localZone(value: string, zone: string): real {
        return Date.fromLocaleString(Qt.locale("C"), value + " " + zone, "yyyyMMdd'T'HHmmss tttt").getTime();
    }

    // Parses a subscription record file. Null when it is not valid records.
    function _parseRecords(json: string): var {
        var parsed;
        try { parsed = JSON.parse(json); } catch (e) { return null; }
        return parsed && Array.isArray(parsed.records) ? parsed : null;
    }

    // Shows an error for a subscription whose records could not be read. The calendar counts as loaded.
    function _recordsFailed(calendar: var, message: string): void {
        calendar.error = message;
        console.error("Calendar: " + message + " for " + calendar.name);
        calendar.loaded = true;
        _rebuild();
        _checkReady();
    }

    function _ingest(path: string, text: string, failed: bool): void {
        var id = _idOfPath(path);
        if (!id) return;
        var calendar = _calendars[id];
        var signature = text.length + ":" + Ics.shortHash(text);
        if (failed && calendar.kind === "link") { _recordsFailed(calendar, calendar.convertError || parserError || recordsErrorText); return; }
        if ((!calendar.document && !calendar.records) || !failed && calendar.signature !== signature) {
            var unnamed = !calendar.name;
            if (calendar.kind === "link") {
                var parsed = _parseRecords(text);
                if (!parsed) { _recordsFailed(calendar, recordsErrorText); return; }
                calendar.records = parsed.records;
                calendar.signature = signature;
                if (unnamed) calendar.name = parsed.name || calendar.file.replace(/\.ics$/i, "");
                // Old records stay on screen as a fallback while a failed conversion shows its error.
                calendar.error = calendar.convertError || "";
            } else {
                calendar.document = Ics.readCalendar(text, _localZone);
                calendar.text = text;
                calendar.signature = signature;
            }
            if (unnamed && calendar.kind !== "link") {
                calendar.name = Ics.calendarName(calendar.document) || calendar.file.replace(/\.ics$/i, "");
            }
            if (unnamed) _saveState();
            _rebuild();
        }
        calendar.loaded = true;
        _checkReady();
    }

    /**
     * Writes one file and returns `Save.writeOutcome`. CalendarFiles sets
     * `blockWrites`, so the write finishes and reports before it returns and the
     * result is known here.
     */
    function _write(path: string, nextText: string, previousText: string, failurePrefix: string): var {
        var outcome = null;
        files.write(path, nextText, function (ok, error) {
            outcome = Save.writeOutcome(ok, error, failurePrefix, previousText, nextText);
        });
        return outcome;
    }

    /**
     * Saves a changed calendar document. On a failed write the document goes
     * back to the text before the edit, the views rebuild, and `saveFailed`
     * and `lastError` carry the error. Returns whether the file was saved.
     * Item actions pass their changed UIDs; bulk actions omit them for a full rebuild.
     */
    function _commit(path: string, uids: var): bool {
        var calendar = _calendars[_idOfPath(path)];
        var nextText = Ics.writeCalendar(calendar.document, _localZone);
        var written = _write(path, nextText, calendar.text, "Could not save " + calendar.name);
        if (written.saved) {
            calendar.text = written.text;
            calendar.signature = written.text.length + ":" + Ics.shortHash(written.text);
            calendar.loaded = true;
        } else {
            calendar.document = Ics.readCalendar(written.text, _localZone);
        }
        lastError = written.error;
        if (uids) _rebuildItem(calendar, uids);
        else _rebuild();
        if (!written.saved) saveFailed(written.error);
        return written.saved;
    }

    // ---- downloads

    function _download(purpose: string, shownUrl: string, url: string, id: string, color, requestId): void {
        files.download({ purpose: purpose, shownUrl: shownUrl, url: url, calendarId: id,
            color: color === undefined || color === null ? "" : String(color), requestId: requestId || 0 });
    }

    function _downloaded(purpose: string, shownUrl: string, url: string, id: string, code: int, jsonPath: string, color: string, requestId: int): void {
        var error = code === files.exitParserMissing ? parserMissingText :
            code === files.exitNotCalendar ? "Not a calendar feed or parser failed" :
            code === files.exitSaveFailed ? "Could not save calendar" : code !== 0 ? Ics.curlError(code) : "";
        var doc = null;
        var json = "";
        if (!error) {
            json = files.readNow(jsonPath) || "";
            doc = _parseRecords(json);
            if (!doc) error = recordsErrorText;
        }
        if (purpose === "check" && jsonPath) Quickshell.execDetached(["sh", "-c",
            'rm -f "$1" "$2"; rmdir "$3"', "sh", jsonPath,
            jsonPath.replace(/feed\.json$/, "feed.ics"), jsonPath.slice(0, jsonPath.lastIndexOf("/"))]);
        if (error) {
            console.error("Calendar: " + error);
            if (code === files.exitParserMissing) parserError = error;
        } else parserError = "";
        var name = doc ? doc.name || Ics.linkHost(url) : "";
        if (purpose === "check") {
            var records = doc ? doc.records : [];
            var calendars = _order.map(function (key) { return _calendars[key]; });
            linkChecked(shownUrl, !error, name, records.length, error,
                doc ? Ics.countStoredDuplicates(records, calendars) : 0);
        } else if (purpose === "subscribe") {
            if (error) { subscribed(shownUrl, "", error, requestId); return; }
            if (_calendars[id]) { subscribed(shownUrl, id, "", requestId); return; }
            var calendar = _addCalendar(id, "link", name, "subscriptions/" + id + ".ics", url, color);
            calendar.records = doc.records;
            calendar.signature = json.length + ":" + Ics.shortHash(json);
            calendar.loaded = true;
            _finishAdd();
            subscribed(shownUrl, id, "", requestId);
        } else {
            var meta = _calendars[id];
            if (!meta) return;
            meta.refreshing = false;
            if (error) {
                meta.error = error;
            } else {
                meta.records = doc.records;
                meta.signature = json.length + ":" + Ics.shortHash(json);
                meta.loaded = true;
                meta.error = "";
                meta.convertError = "";
                meta.colorOverrides = Ics.pruneRecordColorOverrides(meta.colorOverrides, doc.records);
                meta.updatedAt = Date.now();
                _saveState();
            }
            _rebuild();
        }
    }

    // Every link is downloaded again each 30 minutes, and once at start when its cache is older.
    function _refreshLinks(onlyStale: bool): void {
        var limit = Date.now() - 30 * 60000;
        for (var i = 0; i < _order.length; i++) {
            var meta = _calendars[_order[i]];
            if (meta.kind === "link" && (!onlyStale || meta.updatedAt < limit)) refresh(meta.id);
        }
    }

    Timer {
        interval: 30 * 60000
        repeat: true
        running: root.ready
        onTriggered: root._refreshLinks(false)
    }

    onReadyChanged: if (ready) _refreshLinks(true)

    // ---- state file

    function _loadState(values: var): void {
        var saved = Array.isArray(values.calendars) ? values.calendars : [];
        var meta = {};
        var order = [];
        var local = _newMeta("berri", "local", "berri", "berri.ics", "");
        for (var i = 0; i < saved.length; i++) {
            var s = saved[i];
            if (!s || typeof s.id !== "string" || typeof s.file !== "string" || meta[s.id]) continue;
            if (s.id === "berri") { local.color = Ics.cleanColor(s.color) || "accent"; local.hidden = !!s.hidden; continue; }
            if ((s.kind !== "file" && s.kind !== "link") || s.file.indexOf("..") >= 0) continue;
            meta[s.id] = { id: s.id, kind: s.kind, name: String(s.name || ""), color: Ics.cleanColor(s.color) || "accent",
                hidden: !!s.hidden, url: s.kind === "link" ? String(s.url || "") : "", file: s.file, updatedAt: +s.updatedAt || 0,
                colorOverrides: s.kind === "link" ? Ics.pruneColorOverrides(s.colorOverrides, null) : ({}),
                path: dir + "/" + s.file, document: null, records: null, text: "", signature: "", error: "", convertError: "", refreshing: false, loaded: false };
            order.push(s.id);
        }
        meta.berri = local;
        _calendars = meta;
        _order = ["berri"].concat(order);
        _stateRead = true;
        files.active = true;
    }

    function _saveState(): void {
        var list = _order.map(function (id) {
            var m = _calendars[id];
            var out = { id: m.id, kind: m.kind, name: m.name, color: m.color, hidden: m.hidden, file: m.file, updatedAt: m.updatedAt };
            if (m.kind === "link") {
                out.url = m.url;
                if (Object.keys(m.colorOverrides).length > 0) out.colorOverrides = m.colorOverrides;
            }
            return out;
        });
        savedCalendars.save({ calendars: list });
    }

    SavedState {
        id: savedCalendars
        name: "calendars"
        defaults: ({ calendars: [] })
        onLoaded: values => root._loadState(values)
    }

    CalendarFiles {
        id: files
        folder: root.dir
        onListed: paths => root._reconcile(paths)
        onRead: (path, text, failed) => root._ingest(path, text, failed)
        onDownloaded: (request, code, text) => root._downloaded(request.purpose, request.shownUrl,
            request.url, request.calendarId, code, text, request.color, request.requestId)
        onConvertFailed: jsonPath => {
            var id = root._idOfPath(jsonPath);
            if (!id) return;
            root._calendars[id].convertError = root.convertErrorText;
            console.error("Calendar: " + root.convertErrorText + " for " + root._calendars[id].name);
        }
        onParserMissing: {
            root.parserError = root.parserMissingText;
            console.error("Calendar: " + root.parserError);
        }
    }

    // Add new file calendars and drop file calendars whose source is gone.
    function _reconcile(paths: var): void {
        var present = {};
        for (var i = 0; i < paths.length; i++) present[paths[i]] = true;
        var changed = false;
        for (var c = 0; c < _order.length; c++) {
            var calendar = _calendars[_order[c]];
            if (calendar.kind !== "file" || present[calendar.path]) continue;
            delete _calendars[calendar.id];
            changed = true;
        }
        _order = _order.filter(function (id) { return !!_calendars[id]; });
        for (var path in present) {
            var file = path.slice(dir.length + 1);
            if (file.toLowerCase() === "berri.ics" || _idOfPath(path)) continue;
            _addCalendar("f-" + Ics.shortHash(file), "file", "", file, "");
            changed = true;
        }
        _syncPaths();
        if (changed) { _saveState(); _rebuild(); }
    }

    // File readers and readiness follow the same calendar list.
    function _syncPaths(): void {
        files.paths = _order.map(function (id) {
            var calendar = _calendars[id];
            return calendar.kind === "link" ? files.recordPath(calendar.path) : calendar.path;
        });
        _checkReady();
    }

    function _checkReady(): void {
        if (!ready && _stateRead && files.folderReady && _order.every(function (id) { return _calendars[id].loaded; })) ready = true;
    }
}
