.pragma library
.import "Timeline.js" as Timeline

/**
 * The open and close timelines of the two slide panels (the pill dashboard and
 * the theme picker), in ms after the click. The panel QML files read their
 * step lengths and close times from here, so the values live in one place and
 * tests can pin them. Close times use the same ms as the open (time falls
 * while closing). Each close step ends where the next one is about 3/4 done,
 * so the steps overlap and nothing stalls (see Timeline.js).
 */

/** Open steps of the pill dashboard. The icon flight sets its own length, so `totalMs` comes from it. */
var pill = {
    /** The pill widens. */
    widenMs: 420,
    /** The pill grows tall (starts when it is wide). */
    growMs: 500,
    /** The shadow deepens (starts with the growing). */
    shadowMs: 400,
    /** The clock group fades out. */
    clockFadeMs: 140
};

/**
 * Close times of the pill. `totalMs` is the end of the icon flight, `flightCloseEndMs`
 * the time at which the icon flight is at rest.
 */
function pillClose(totalMs, flightCloseEndMs) {
    // The dashboard fades and slides out, the shadow and the height start to fall, 60 ms after the close starts.
    var growCloseAtMs = totalMs - 60;
    // The pill narrows when the height has fallen 3/4.
    var widenCloseAtMs = Timeline.overlapEnd(growCloseAtMs, pill.growMs, Timeline.bigStepHandover);
    // The clock returns when the pill has narrowed 3/5.
    var clockCloseAtMs = Timeline.overlapEnd(widenCloseAtMs, pill.widenMs, Timeline.smallStepHandover);
    return {
        growCloseAtMs: growCloseAtMs,
        widenCloseAtMs: widenCloseAtMs,
        clockCloseAtMs: clockCloseAtMs,
        // The time at which every step of the close is at rest.
        closeEndMs: Math.min(
            Timeline.closeEnd(widenCloseAtMs, pill.widenMs),
            Timeline.closeEnd(clockCloseAtMs, pill.clockFadeMs),
            flightCloseEndMs)
    };
}

/** Open steps of the theme picker. */
var picker = (function () {
    var narrowMs = 420;
    var wideStartMs = 470;
    var headerStartMs = wideStartMs + 40;
    var headerMs = 280;
    var stripFadeStartMs = headerStartMs + headerMs;
    var stripFadeMs = 160;
    return {
        /** The notch widens to the narrow picker. */
        narrowMs: narrowMs,
        /** The notch grows tall and its corners round. */
        riseMs: 480,
        /** The shadow deepens. */
        shadowMs: 400,
        /** The picker widens; starts when the narrow picker is almost done. */
        wideStartMs: wideStartMs,
        wideMs: 420,
        /** The header and body fade in, a little after the widening starts. */
        headerStartMs: headerStartMs,
        headerMs: headerMs,
        /** The strip fades out once the header is fully opaque. */
        stripFadeStartMs: stripFadeStartMs,
        stripFadeMs: stripFadeMs,
        /** The whole open motion. */
        totalMs: stripFadeStartMs + stripFadeMs
    };
})();

/** Close times of the picker. `stripSpanMs` is the time one full morph of the palette strip takes. */
function pickerClose(stripSpanMs) {
    // The strip returns and the header fades out at once; the wide picker narrows 40 ms later.
    var wideCloseAtMs = picker.totalMs - 40;
    // The notch shrinks to its bar when the wide picker has narrowed 3/4.
    var narrowCloseAtMs = Timeline.overlapEnd(wideCloseAtMs, picker.wideMs, Timeline.bigStepHandover);
    // The bars of the strip return with the shrinking.
    var stripCloseAtMs = narrowCloseAtMs + (stripSpanMs - picker.narrowMs);
    return {
        wideCloseAtMs: wideCloseAtMs,
        narrowCloseAtMs: narrowCloseAtMs,
        stripCloseAtMs: stripCloseAtMs,
        closeEndMs: Math.min(
            Timeline.closeEnd(narrowCloseAtMs, picker.riseMs),
            Timeline.closeEnd(narrowCloseAtMs, picker.narrowMs),
            stripCloseAtMs - stripSpanMs)
    };
}
