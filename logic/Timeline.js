.pragma library
.import "Ease.js" as Ease

/**
 * Helpers for one open/close motion that runs from a single straight-line
 * progress value. The caller turns progress into milliseconds since the open
 * started (`elapsedMs`) and gives each part a window (start, length). Each part
 * then shows its own slice of the motion. Close plays progress backwards, so
 * the parts run in reversed order. Each part is eased the other way round
 * while closing (`closing` true): it leaves fast and settles slowly into rest,
 * like it does when it opens. The open values stay as they are.
 */

/** Straight-line 0..1 position of `elapsedMs` inside the window that starts at `startMs` and lasts `durationMs`. */
function slice(elapsedMs, startMs, durationMs) {
    if (durationMs <= 0) return elapsedMs >= startMs ? 1 : 0;
    var phase = (elapsedMs - startMs) / durationMs;
    return phase <= 0 ? 0 : (phase >= 1 ? 1 : phase);
}

/**
 * The window of a part while closing: it has the same length, but it ends at
 * `closeAtMs` (default: where the open window ends). The part starts to leave
 * when `elapsedMs` falls to `closeAtMs`. Parts that follow one another can
 * overlap, so the close does not stop between two steps.
 */
function closeSlice(elapsedMs, startMs, durationMs, closeAtMs) {
    var endMs = closeAtMs === undefined ? startMs + durationMs : closeAtMs;
    return slice(elapsedMs, endMs - durationMs, durationMs);
}

/**
 * The spring curve over one window: slice() through spring(). While closing,
 * the mirror over the close window: 1 - spring(1 - phase). The phase falls
 * from 1 to 0 then, and the value leaves 1 fast and settles slowly onto 0.
 */
function springSlice(elapsedMs, startMs, durationMs, closing, closeAtMs) {
    if (!closing) return Ease.spring(slice(elapsedMs, startMs, durationMs));
    return 1 - Ease.spring(1 - closeSlice(elapsedMs, startMs, durationMs, closeAtMs));
}

/**
 * A fade over one window. Opening it is the straight slice(). While closing it
 * is the same mirror as springSlice, so a fade does not stop hard at its end.
 */
function fadeSlice(elapsedMs, startMs, durationMs, closing, closeAtMs) {
    if (!closing) return slice(elapsedMs, startMs, durationMs);
    return 1 - Ease.spring(1 - closeSlice(elapsedMs, startMs, durationMs, closeAtMs));
}
