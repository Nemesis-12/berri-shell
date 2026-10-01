.pragma library

/**
 * The rule after one calendar file write. A saved write keeps the new text.
 * A failed write goes back to the text before the edit and gives an error
 * message of the form "<failurePrefix>: <error>". Result: `saved`, the `text`
 * the calendar must hold, and `error` ("" when saved).
 */
function writeOutcome(ok, error, failurePrefix, previousText, nextText) {
    return {
        saved: ok,
        text: ok ? nextText : previousText,
        error: ok ? "" : failurePrefix + ": " + error,
    };
}
