import QtQuick
import "../logic/CalendarQueries.js" as Queries
import "../logic/CalendarSave.js" as Save

/**
 * Imports and writes calendar files. Calendar supplies write text and accepts
 * results through named operations on `store`. `files` supplies file access.
 * Stored documents, read status and view updates stay with Calendar.
 */
QtObject {
    id: disk

    required property QtObject store
    required property CalendarFiles files

    /** Reports why an import was refused. */
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
        var text = files.readNow(from);
        if (text === null) return fail("Cannot read the file");
        if (!Queries.looksLikeCalendar(text)) return fail("Not a calendar file");
        var prepared = store.prepareCalendarImport(from, text);
        if (prepared.existingId) return prepared.existingId;
        var written = write(prepared.path, text, "", "Could not import calendar");
        if (!written.saved) { store.lastError = written.error; return ""; }
        return store.acceptCalendarImport(prepared, text, color);
    }

    /**
     * Writes one file and returns `Save.writeOutcome`. CalendarFiles sets
     * `blockWrites`, so the write finishes and reports before it returns and the
     * result is known here.
     */
    function write(path: string, nextText: string, previousText: string, failurePrefix: string): var {
        var outcome = null;
        files.write(path, nextText, function (ok, error) {
            outcome = Save.writeOutcome(ok, error, failurePrefix, previousText, nextText);
        });
        return outcome;
    }

    /** Saves item edits and rebuilds only their changed months. */
    function commitItems(path: string, uids: var): bool {
        return saveAndRebuild(path, uids);
    }

    /** Saves calendar-wide changes and clears all cached months. */
    function commitCalendar(path: string): bool {
        return saveAndRebuild(path);
    }

    /** Writes the prepared text and lets Calendar apply the result. */
    function saveAndRebuild(path: string, uids): bool {
        var prepared = store.prepareCalendarWrite(path);
        var written = write(path, prepared.nextText, prepared.previousText, prepared.failurePrefix);
        return store.acceptCalendarWrite(path, written, uids);
    }
}
