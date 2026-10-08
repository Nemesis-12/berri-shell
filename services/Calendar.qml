pragma Singleton
import QtQuick
import Quickshell
import "../logic/CalendarCatalog.js" as Catalog
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items
import "../logic/CalendarMonths.js" as Months
import "../logic/CalendarQueries.js" as Queries
import "../logic/CalendarZone.js" as Zone
import "../logic/Times.js" as Times

/**
 * berri's calendars. Three kinds: "local" (berri.ics, always there), "file"
 * (an .ics file in ~/.local/share/berri-shell/calendar/, editable) and "link"
 * (a subscribed https:// or webcal:// feed, read-only, cached in
 * calendar/subscriptions/ and refreshed every 30 minutes). The folder is
 * watched: .ics files added or removed while berri runs are picked up.
 * Name, color, hidden and link data are kept in ~/.local/state/berri-shell/calendars.json.
 * Answers day and month queries and saves each change at once (atomic write).
 * New items go to berri.ics. The file format and the item shape are described
 * at the top of CalendarItems.js.
 *
 * Views read Calendar.itemsOn(date) or Calendar.itemsInMonth(year, month) inside
 * a binding. Both read `revision`, so the binding runs again after every change.
 * The cache limit is CalendarMonths.js MONTH_CACHE_LIMIT (eight months). Item edits keep
 * unchanged months; imports and calendar-wide settings clear them.
 * Do not edit the arrays.
 * The same event in several calendars shows once (see CalendarItems.js): the copy
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

    readonly property string dir: FolderRoots.calendar
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
    /** How many Calendar tabs show `saveFailed` messages (see WhileVisible.qml, counter "saveErrorViewers"). */
    property int saveErrorViewers: 0
    /** True while a Calendar tab shows `saveFailed` messages. When false, the notifier shows them as a desktop notification. */
    readonly property bool saveErrorShown: saveErrorViewers > 0

    // ---- queries

    /** Occurrences on one day, in day order (all-day first, then by time). */
    function itemsOn(date): var {
        var key = Items.toKey(date);
        var month = itemsInMonth(+key.slice(0, 4), +key.slice(5, 7));
        return month[key] || [];
    }

    /** { "YYYY-MM-DD": [occurrence] } for one month. Each occurrence has a `color` (a preset key or "#rrggbb"), `hasOwnColor`, `calendarId`, `readOnly`, `alsoIn` (names of the calendars with a duplicate) and `alsoInIds`. Hidden calendars give nothing. */
    function itemsInMonth(year: int, month: int): var {
        void root.revision;
        return Months.cachedItemsInMonth(_months, year, month);
    }

    /** The selected item for the detail form, or null. Editable items keep their full document fields. */
    function getItem(uid: string): var {
        void root.revision;
        var found = _locate(uid, false);
        if (!found) return null;
        return Items.shownItem(Queries.withColorOverride(_storedItem(found), found.meta.colorOverrides));
    }

    /** The selected item as a projected item: a copy with its calendarId and readOnly. Link records become stored items first. */
    function _storedItem(found: var): var {
        if (found.doc) return Items.projectedItem(found.doc.items[found.index], found.meta.id, false);
        return Items.projectedItem(Format.expandCompactItem(found.meta.records[found.index]), found.meta.id, true);
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
        var clean = clear ? "" : Items.cleanColor(color);
        if (!clear && !clean) return false;
        var item = _storedItem(found);
        if (!item.readOnly) return update(uid, { color: clean || "accent" });
        var meta = _calendars[item.calendarId];
        if (!meta) return false;
        meta.colorOverrides = Catalog.withItemColor(meta.colorOverrides, item.uid, clean);
        _saveState();
        _rebuildItem(meta, [item.uid]);
        return true;
    }

    // ---- changes. Each one saves the file and bumps revision.

    /** Adds an item to berri.ics, or to the file calendar in `calendarId` (fields as in CalendarItems.js, at least date; `color` is a preset key or "#rrggbb", default "accent"). Returns true when the item is saved. */
    function add(fields: var): bool {
        var path = defaultPath;
        var target = fields.calendarId ? _calendars[fields.calendarId] : null;
        if (fields.calendarId && (!target || target.kind === "link")) return false;
        if (target) path = dir + "/" + target.file;
        var calendar = target || _calendars.berri;
        if (!disk.canWrite(calendar)) return false;
        var doc = calendar.document || Format.emptyCalendar();
        var item = Items.makeItem(Catalog.cleanDates(fields));
        doc.items.push(item);
        calendar.document = doc;
        return disk.commitItems(path, [item.uid]);
    }

    /** Changes fields of the whole item (all occurrences of a repeating one). */
    function update(uid: string, changes: var): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        found.doc.items[found.index] = Items.applyChanges(found.doc.items[found.index], Catalog.cleanDates(changes));
        return disk.commitItems(found.path, [found.doc.items[found.index].uid]);
    }

    /** Deletes an item, or only one occurrence when occurrenceDate is given for a repeating item. */
    function remove(uid: string, occurrenceDate): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        var item = found.doc.items[found.index];
        var day = Catalog.optionalKey(occurrenceDate);
        var kept = day ? Items.withoutOccurrence(item, day) : null;
        if (kept) found.doc.items[found.index] = kept;
        else found.doc.items.splice(found.index, 1);
        return disk.commitItems(found.path, [item.uid]);
    }

    /** Ticks an item off. For a repeating item only that occurrence (occurrenceDate). */
    function setDone(uid: string, done: bool, occurrenceDate): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        var item = found.doc.items[found.index];
        found.doc.items[found.index] = Items.withDone(item, Catalog.optionalKey(occurrenceDate) || item.date, done);
        return disk.commitItems(found.path, [item.uid]);
    }

    /**
     * Moves one occurrence to another day. A repeating item keeps its series
     * (minus that day) and gets a new single item on the new day. Optional
     * changes (for example { time: "18:00" }) apply to the moved item.
     */
    function move(uid: string, fromDate, toDate, changes: var): bool {
        var found = _locate(uid, true);
        if (!found) return false;
        var moved = Items.moveOccurrence(found.doc.items[found.index], Items.toKey(fromDate), Items.toKey(toDate), Catalog.cleanDates(changes || {}));
        found.doc.items[found.index] = moved.item;
        if (moved.created) found.doc.items.push(moved.created);
        return disk.commitItems(found.path, moved.created ? [moved.item.uid, moved.created.uid] : [moved.item.uid]);
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
        var to = Items.snoozeReminder(item.time, Items.toKey(occurrenceDate), item.alarmMinutes, amount, Items.toKey(now), nowTime);
        var changes = { time: to.time };
        if (item.alarmMinutes > 0 && to.alarmMinutes !== item.alarmMinutes) changes.alarmMinutes = to.alarmMinutes;
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
    function importFile(path: string, color): string { return disk.importFile(path, color); }

    /** Downloads a link and reports what is in it. Nothing is saved. Result: `linkChecked`. */
    function checkLink(url: string): void { links.check(url); }

    /** Returns the request id. The subscribed result carries the same id. */
    function subscribe(url: string, color): int { return links.subscribe(url, color); }

    /** Downloads a link calendar again now. A failure keeps the old items and sets `error`. */
    function refresh(id: string): void { links.refresh(id); }

    /** Removes a file or link calendar and its file. The local calendar stays. */
    function removeCalendar(id: string): bool {
        var meta = _calendars[id];
        if (!meta || meta.kind === "local") return false;
        var path = dir + "/" + meta.file;
        delete _calendars[id];
        _order = _order.filter(function (o) { return o !== id; });
        files.cancelDownloads(id);
        files.removeFile(path);
        _applyCalendarListChange();
        return true;
    }

    function setCalendarColor(id: string, color: string): void {
        var clean = Items.cleanColor(color);
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
        return Queries.newCalendarColor("", _usedColors());
    }

    /**
     * Sets the calendar color and removes every own color of its items, so all
     * items show the calendar color. Link: drops its color overrides. File: clears
     * X-BERRI-COLOR in the file. The local berri calendar is not allowed (false).
     * One save and one revision step. Returns false for an unknown id or a bad color.
     */
    function applyColorToCalendar(id: string, color: string): bool {
        var meta = _calendars[id];
        var clean = Items.cleanColor(color);
        if (!meta || meta.kind === "local" || !clean) return false;
        var previousColor = meta.color;
        meta.color = clean;
        var path = dir + "/" + meta.file;
        var doc = meta.document;
        var fileChanged = false;
        if (meta.kind === "link") meta.colorOverrides = ({});
        else if (doc) fileChanged = Items.clearItemColors(doc.items) > 0;
        if (fileChanged && !disk.commitCalendar(path)) {
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
    property var _months: Months.createMonthCache([])
    property bool _stateRead: false
    property int _nextSubscription: 0

    /** The item and its file, or null. Items of link calendars are found only for reading. */
    function _locate(uid: string, forEdit: bool): var {
        var identity = Items.itemIdentity(uid);
        var meta = identity ? _calendars[identity.calendarId] : null;
        if (!meta || forEdit && meta.kind === "link") return null;
        if (forEdit && !disk.canWrite(meta)) return null;
        var doc = meta.document;
        var items = doc ? doc.items : meta.records || [];
        var index = Items.itemIndex(items, uid, meta.id);
        return index < 0 ? null : { path: meta.path, doc: doc, meta: meta, index: index };
    }

    function _idOfPath(path: string): string {
        return Catalog.idOfPath(_order, _calendars, path, files.recordPath);
    }

    function _usedColors(): var {
        return _order.map(function (o) { return _calendars[o].color; });
    }

    function _newMeta(id: string, kind: string, name: string, file: string, color): var {
        return Catalog.newMeta(dir, id, kind, name, file, color, _usedColors());
    }

    function _addCalendar(id: string, kind: string, name: string, file: string, url: string, color): var {
        var unique = Catalog.uniqueId(_calendars, id);
        var meta = _newMeta(unique, kind, name, file, color);
        meta.url = url;
        meta.updatedAt = kind === "local" ? 0 : Date.now();
        _calendars[unique] = meta;
        _order = _order.concat([unique]);
        return meta;
    }

    // After any change to the calendar list (add, remove, load): adjusts the FileViews, saves state and rebuilds.
    function _applyCalendarListChange(): void {
        _syncPaths();
        _saveState();
        _rebuild();
    }

    // Replace every derived list together before notifying the views.
    function _rebuild(): void {
        _months = Months.createMonthCache(_order.map(function (id) { return _calendars[id]; }));
        revision++;
    }

    // Shows the new update time of a feed that did not change. Cached months stay.
    function _refreshRow(calendar: var): void {
        Months.refreshCalendarRow(_months, calendar);
        revision++;
    }

    // Reproject one calendar and keep months whose edited occurrences did not change.
    function _rebuildItem(calendar: var, uids: var): void {
        Months.editMonthCache(_months, calendar, uids);
        revision++;
    }

    // Converts an IANA zone clock to an instant with the system zone database.
    function _localZone(value: string, zone: string): real {
        return Zone.instant(value, zone);
    }

    onReadyChanged: if (ready) links.refreshAll(true)

    function readErrorText(name: string): string { return "Could not read " + name; }

    // ---- state file

    function _loadState(values: var): void {
        var restored = Catalog.restoreCalendars(dir, values);
        _calendars = restored.calendars;
        _order = restored.order;
        _stateRead = true;
        files.active = true;
    }

    function _saveState(): void {
        savedCalendars.save({ calendars: Catalog.savedList(_order, _calendars) });
    }

    SavedState {
        id: savedCalendars
        name: "calendars"
        defaults: ({ calendars: [] })
        onLoaded: values => root._loadState(values)
    }

    CalendarDisk {
        id: disk
        store: root
    }

    CalendarLinks {
        id: links
        store: root
    }

    /** The file access, for CalendarDisk and CalendarLinks. */
    readonly property alias _files: files

    CalendarFiles {
        id: files
        folder: root.dir
        onListed: paths => root._reconcile(paths)
        onRead: (path, text, failed) => disk.ingest(path, text, failed)
        onDownloaded: (request, code, jsonPath) => links.downloaded(request, code, jsonPath)
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
        var missing = Catalog.missingFileIds(_order, _calendars, paths);
        for (var m = 0; m < missing.length; m++) delete _calendars[missing[m]];
        _order = _order.filter(function (id) { return !!_calendars[id]; });
        var names = Catalog.newFileNames(dir, paths, function (path) { return !!_idOfPath(path); });
        for (var i = 0; i < names.length; i++) _addCalendar("f-" + Items.shortHash(names[i]), "file", "", names[i], "");
        _syncPaths();
        if (missing.length > 0 || names.length > 0) { _saveState(); _rebuild(); }
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
