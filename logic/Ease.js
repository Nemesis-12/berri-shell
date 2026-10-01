.pragma library

// BezierSpline control points shared by the QML animations.
var springCurve = [0.32, 0.72, 0, 1, 1, 1];
var standardCurve = [0.4, 0, 0.2, 1, 1, 1];
/** Fast start, long soft stop: cubic-bezier(.2, 0, 0, 1). */
var emphasizedCurve = [0.2, 0, 0, 1, 1, 1];

/** Evaluates springCurve for a straight-line phase from 0 to 1. */
function spring(phase) {
    if (phase <= 0) return 0;
    if (phase >= 1) return 1;
    // Solve x(t) = 1.96t^3 - 1.92t^2 + 0.96t with Cardano's formula.
    var a = -1.92 / 1.96;
    var b = 0.96 / 1.96;
    var c = -phase / 1.96;
    var p = b - a * a / 3;
    var q = 2 * a * a * a / 27 - a * b / 3 + c;
    var root = Math.sqrt(q * q / 4 + p * p * p / 27);
    var t = Math.cbrt(-q / 2 + root) + Math.cbrt(-q / 2 - root) - a / 3;
    return 0.16 * t * t * t - 1.32 * t * t + 2.16 * t;
}

/**
 * The mock's ease-out curve, cubic-bezier(.4, 0, .2, 1), as a function of a
 * straight-line phase 0..1. Open and close views drive a linear phase and show
 * this value, so close is exactly open played backwards.
 *
 * The curve's x(t) = 1.2t - 1.8t^2 + 1.6t^3 has one real root for every phase
 * (its slope is always positive), so t comes from Cardano's formula in one step.
 */
function easeOut(phase) {
    if (phase <= 0) return 0;
    if (phase >= 1) return 1;
    // t^3 - 1.125 t^2 + 0.75 t - phase / 1.6 = 0, with t = s + 0.375: s^3 + p s + q = 0.
    var p = 0.328125;
    var q = 0.17578125 - phase / 1.6;
    var root = Math.sqrt(q * q / 4 + p * p * p / 27);
    var t = Math.cbrt(-q / 2 + root) + Math.cbrt(-q / 2 - root) + 0.375;
    var v = 1 - t;
    return 3 * v * t * t + t * t * t;
}
