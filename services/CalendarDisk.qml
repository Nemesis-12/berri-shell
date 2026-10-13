import QtQuick
import "../logic/CalendarFormat.js" as Format
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
        store.failCalendarImport(message);
        return "";
    }

    /** Copies an .ics file into the calendar folder as a new file calendar (see Calendar.importFile). */
    function importFile(path: string, color): string {
        store.beginCalendarImport();
        var from = String(path).replace(/^file:\/\//, "");
        if (!/\.ics$/i.test(from)) return fail("Not an .ics file");
        var text = files.readNow(from);
        if (text == null) return fail("Cannot read the file");
        if (!Format.isCompleteCalendar(text)) return fail("Not a calendar file");
        var prepared = store.prepareCalendarImport(from, text);
        if (prepared.existingId) return prepared.existingId;
        var written = write(prepared.path, text, "", "Could not import calendar");
        if (!written.saved) return fail(written.error);
        return store.acceptCalendarImport(prepared, text, color);
    }

    /**
     * Writes one file and returns `Save.writeOutcome`. CalendarFiles sets
     * `blockWrites`, so the write finishes and reports before it returns and the
     * result is known here.
     */
    function write(path: string, nextText: string, previousText: var, failurePrefix: string): var {
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

    /** Refuses stale edits and reloads the current file before a replacement. */
    function checkCurrent(path: string, prepared: var, uids): bool {
        var currentText = files.readNow(path);
        var missingLocal = currentText === undefined && path === files.folder + "/berri.ics";
        if (currentText === null || currentText !== prepared.previousText && !(missingLocal && prepared.previousText === null)) {
            var error = currentText == null && !missingLocal ? "Could not read the file" : "File changed on disk. Check the calendar and try again";
            var refused = Save.writeOutcome(false, error, prepared.failurePrefix, prepared.previousText, prepared.nextText);
            store.acceptCalendarWrite(path, refused, uids);
            if (currentText === undefined) store.acceptCalendarMissing(path);
            else store.acceptCalendarRead(path, currentText === null ? "" : currentText, currentText === null);
            return false;
        }
        return true;
    }

    /** Writes the prepared text and lets Calendar apply the result. */
    function saveAndRebuild(path: string, uids): bool {
        var prepared = store.prepareCalendarWrite(path);
        if (!prepared || !checkCurrent(path, prepared, uids)) return false;
        // One atomic backup must finish before the calendar is replaced. A new
        // local calendar has null previous text because no file exists yet.
        if (prepared.previousText !== null) {
            var backup = write(path + ".bak", prepared.previousText, prepared.previousText, prepared.failurePrefix + " backup");
            if (!backup.saved) return store.acceptCalendarWrite(path, backup, uids);
        }
        // The backup write gives another process time to change the file.
        if (!checkCurrent(path, prepared, uids)) return false;
        var written = write(path, prepared.nextText, prepared.previousText, prepared.failurePrefix);
        return store.acceptCalendarWrite(path, written, uids);
    }
}
