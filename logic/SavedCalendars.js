.pragma library
.import "CalendarIdentity.js" as Identity

/**
 * True when a saved calendar entry names files only inside the calendar
 * folder. The id becomes part of a file name, so it uses a small set of
 * characters. A link keeps its file at subscriptions/<id>.ics; a file
 * calendar is one .ics name in the folder itself (berri.ics is the local
 * calendar and is never listed). The link address is checked separately.
 */
function isSafeEntry(entry) {
    if (!entry || typeof entry.id !== "string" || typeof entry.file !== "string") return false;
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(entry.id)) return false;
    if (entry.kind === "link") return entry.file === "subscriptions/" + entry.id + ".ics";
    if (entry.kind !== "file") return false;
    return /^[^\/\0.][^\/\0]*\.ics$/i.test(entry.file) && entry.file.toLowerCase() !== Identity.LOCAL_FILE;
}
