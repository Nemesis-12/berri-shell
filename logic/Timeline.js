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
 *
 * The spring curve spends the last third of its time on the last few percent
 * of the way. In a tall panel that is a visible slow tail after the close
 * looks finished. So a closing part runs over `closeShare` of its window, and
 * it is within 1 px of rest at the end of that shorter window.
 */

/** The part of its open window that a closing part takes (0..1). Used only in this file. */
var closeShare = 0.6;

/**
 * The elapsed time at which a closing part is at rest: its close window ends
 * at `closeAtMs` and is `closeShare` of the open window of `durationMs`.
 */
function closeEnd(closeAtMs, durationMs) {
    return closeAtMs - durationMs * closeShare;
}

/** Straight-line 0..1 position of `elapsedMs` inside the window that starts at `startMs` and lasts `durationMs`. */
function slice(elapsedMs, startMs, durationMs) {
    if (durationMs <= 0) return elapsedMs >= startMs ? 1 : 0;
    var phase = (elapsedMs - startMs) / durationMs;
    return phase <= 0 ? 0 : (phase >= 1 ? 1 : phase);
}

/**
 * The straight-line window of a part while closing: it has the length given, and it ends at
 * `closeAtMs` (default: where the open window ends). The part starts to leave
 * when `elapsedMs` falls to `closeAtMs`. Parts that follow one another can
 * overlap, so the close does not stop between two steps.
 */
function closeSlice(elapsedMs, startMs, durationMs, closeAtMs) {
    var endMs = closeAtMs === undefined ? startMs + durationMs : closeAtMs;
    return slice(elapsedMs, endMs - durationMs, durationMs);
}

/**
/**
 * The mirror of the spring curve over the close window of a part (the window
 * from closeEnd() to `closeAtMs`, default: where the open window ends):
 * 1 - spring(1 - phase). The phase falls from 1 to 0 then, and the value
 * leaves 1 fast and settles slowly onto 0.
 */
function closingSpring(elapsedMs, startMs, durationMs, closeAtMs) {
    var endMs = closeAtMs === undefined ? startMs + durationMs : closeAtMs;
    return 1 - Ease.spring(1 - slice(elapsedMs, closeEnd(endMs, durationMs), durationMs * closeShare));
}

/**
 * The spring curve over one window: slice() through spring(). While closing,
 * closingSpring(): the part is at rest from closeEnd() on.
 */
function springSlice(elapsedMs, startMs, durationMs, closing, closeAtMs) {
    if (!closing) return Ease.spring(slice(elapsedMs, startMs, durationMs));
    return closingSpring(elapsedMs, startMs, durationMs, closeAtMs);
}

/**
 * A fade over one window. Opening it is the straight slice(). While closing it
 * is the same mirror as springSlice (closingSpring), so a fade does not stop hard at its end.
 */
function fadeSlice(elapsedMs, startMs, durationMs, closing, closeAtMs) {
    if (!closing) return slice(elapsedMs, startMs, durationMs);
    return closingSpring(elapsedMs, startMs, durationMs, closeAtMs);
}
