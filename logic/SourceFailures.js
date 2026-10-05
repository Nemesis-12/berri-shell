.pragma library

/**
 * When a data source writes its failure to the shell log.
 * A source writes one line for its first failure. It writes no more lines
 * until PERIOD_MS has passed since that line, however many retries fail.
 * Each source has its own period. A good refresh does not restart it.
 * The line holds the source name and one fixed reason from REASONS.
 * It never holds response text, URLs, paths or error objects.
 */

/** The log period of one source: one hour. */
var PERIOD_MS = 60 * 60 * 1000;

var REASONS = ["offline", "bad data", "no location", "no output", "bad output"];

/** True when a source that last logged at `lastAt` (0: never) may log at `now`. */
function shouldLog(lastAt, now, period) {
    return !lastAt || now - lastAt >= (period || PERIOD_MS) || now < lastAt;
}

/** The log line of a failure. A reason outside REASONS shows as "unknown". */
function line(source, reason) {
    return "berri-shell: " + source + " data failed (" + (REASONS.indexOf(reason) >= 0 ? reason : "unknown") + ")";
}

/**
 * Call at each failure. `lastLogged` is one object kept by the service; it
 * holds the time of the last line of each source. Returns the line to write,
 * or "" when the source is inside its period.
 */
function report(lastLogged, source, reason, now) {
    if (!shouldLog(lastLogged[source] || 0, now)) return "";
    lastLogged[source] = now;
    return line(source, reason);
}

/** The reason for an unreadable script answer: no text at all, or text that is not the expected data. */
function outputReason(text) {
    return text ? "bad output" : "no output";
}
