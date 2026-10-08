import QtQuick
import "../logic/CalendarCatalog.js" as Catalog
import "../logic/CalendarFormat.js" as Format
import "../logic/CalendarItems.js" as Items
import "../logic/CalendarQueries.js" as Queries
import "../logic/CalendarSave.js" as Save

/**
 * The file side of Calendar.qml: takes in what was read from a file, and
 * saves changed documents. `store` is the Calendar singleton that owns the
 * calendars; this part only reads and changes them.
 */
QtObject {
    id: disk

    required property var store

    /**
     * True when an edit may write this calendar. After a failed read, the
     * file may hold changes berri never saw, so a write could overwrite them.
     * Such a calendar reads the file again first. If that fails, the
     * edit is refused and `saveFailed` carries the read error.
     */
    function canWrite(calendar: var): bool {
        if (!calendar.readFailed) return true;
        var text = store._files.readNow(calendar.path);
        if (text !== null) {
            ingest(calendar.path, text, false);
            return true;
        }
        store.lastError = store.readErrorText(calendar.name);
        store.saveFailed(store.lastError);
        return false;
    }

    // Shows an error for a subscription whose records could not be read. The calendar counts as loaded.
    function recordsFailed(calendar: var, message: string): void {
        calendar.error = message;
        console.error("Calendar: " + message + " for " + calendar.name);
        calendar.loaded = true;
        store._rebuild();
        store._checkReady();
    }

    // A file could not be read. Keep any cached document for display, but refuse edits until a read succeeds.
    function readFailed(calendar: var): void {
        calendar.readFailed = true;
        calendar.error = store.readErrorText(calendar.name);
        calendar.loaded = true;
        store._rebuild();
        store._checkReady();
    }

    // Puts the read text of a link's records file into the calendar.
    function takeRecords(calendar: var, text: string, signature: string, unnamed: bool): bool {
        var parsed = Catalog.parseRecords(text);
        if (!parsed) { recordsFailed(calendar, store.recordsErrorText); return false; }
        calendar.records = parsed.records;
        calendar.signature = signature;
        if (unnamed) calendar.name = parsed.name || calendar.file.replace(/\.ics$/i, "");
        // Old records stay on screen as a fallback while a failed conversion shows its error.
        calendar.error = calendar.convertError || "";
        return true;
    }

    function ingest(path: string, text: string, failed: bool): void {
        var id = store._idOfPath(path);
        if (!id) return;
        var calendar = store._calendars[id];
        if (failed && calendar.kind !== "link") { readFailed(calendar); return; }
        if (!failed) { calendar.readFailed = false; if (calendar.kind !== "link") calendar.error = ""; }
        var signature = text.length + ":" + Items.shortHash(text);
        if (failed && calendar.kind === "link") { recordsFailed(calendar, calendar.convertError || store.parserError || store.recordsErrorText); return; }
        if ((!calendar.document && !calendar.records) || !failed && calendar.signature !== signature) {
            var unnamed = !calendar.name;
            if (calendar.kind === "link") {
                if (!takeRecords(calendar, text, signature, unnamed)) return;
            } else {
                calendar.document = Format.readCalendar(text, store._localZone);
                calendar.text = text;
                calendar.signature = signature;
                if (unnamed) calendar.name = Queries.calendarName(calendar.document) || calendar.file.replace(/\.ics$/i, "");
            }
            if (unnamed) store._saveState();
            store._rebuild();
        }
        calendar.loaded = true;
        store._checkReady();
    }

    function fail(message: string): string {
        store.lastError = message;
        return "";
    }

    /** Copies an .ics file into the calendar folder as a new file calendar (see Calendar.importFile). */
    function importFile(path: string, color): string {
        store.lastError = "";
        store.lastImportDuplicates = 0;
        var from = String(path).replace(/^file:\/\//, "");
        if (!/\.ics$/i.test(from)) return fail("Not an .ics file");
        var text = store._files.readNow(from);
        if (text === null) return fail("Cannot read the file");
        if (!Queries.looksLikeCalendar(text)) return fail("Not a calendar file");
        for (var i = 0; i < store._order.length; i++) {
            var other = store._calendars[store._order[i]];
            if (other.kind === "file" && other.text === text) return other.id;
        }
        var file = Catalog.importFileName(from, function (name) { return Catalog.fileTaken(store._order, store._calendars, name); });
        var doc = Format.readCalendar(text, store._localZone);
        var duplicates = Queries.countDuplicates(doc.items, Catalog.existingItems(store._order, store._calendars));
        var written = write(store.dir + "/" + file, text, "", "Could not import calendar");
        if (!written.saved) { store.lastError = written.error; return ""; }
        var name = Queries.calendarName(doc) || Catalog.importStem(from);
        var meta = store._addCalendar("f-" + Items.shortHash(file), "file", name, file, "", color);
        meta.document = doc;
        meta.text = text;
        meta.signature = text.length + ":" + Items.shortHash(text);
        meta.loaded = true;
        store._applyCalendarListChange();
        store.lastImportDuplicates = duplicates;
        return meta.id;
    }

    /**
     * Writes one file and returns `Save.writeOutcome`. CalendarFiles sets
     * `blockWrites`, so the write finishes and reports before it returns and the
     * result is known here.
     */
    function write(path: string, nextText: string, previousText: string, failurePrefix: string): var {
        var outcome = null;
        store._files.write(path, nextText, function (ok, error) {
            outcome = Save.writeOutcome(ok, error, failurePrefix, previousText, nextText);
        });
        return outcome;
    }

    /** Saves item edits and rebuilds only their changed months. */
    function commitItems(path: string, uids: var): bool {
        return saveAndRebuild(path, function (calendar) { store._rebuildItem(calendar, uids); });
    }

    /** Saves calendar-wide changes and clears all cached months. */
    function commitCalendar(path: string): bool {
        return saveAndRebuild(path, function () { store._rebuild(); });
    }

    /**
     * Saves a changed calendar document. On a failed write the document goes
     * back to the text before the edit, the views rebuild, and `saveFailed`
     * and `lastError` carry the error. Returns whether the file was saved.
     * The caller supplies the rebuild for both a saved edit and a restored document.
     */
    function saveAndRebuild(path: string, rebuild: var): bool {
        var calendar = store._calendars[store._idOfPath(path)];
        var nextText = Format.writeCalendar(calendar.document, store._localZone);
        var written = write(path, nextText, calendar.text, "Could not save " + calendar.name);
        if (written.saved) {
            calendar.text = written.text;
            calendar.signature = written.text.length + ":" + Items.shortHash(written.text);
            calendar.loaded = true;
        } else {
            calendar.document = Format.readCalendar(written.text, store._localZone);
        }
        store.lastError = written.error;
        rebuild(calendar);
        if (!written.saved) store.saveFailed(written.error);
        return written.saved;
    }
}
