.pragma library

/**
 * Device pixel ratio to use: the screen's Screen.devicePixelRatio, or 1 when it
 * is 0 or less. Use as: readonly property real dpr: PixelGrid.dpr(Screen.devicePixelRatio)
 */
function dpr(devicePixelRatio) {
    return devicePixelRatio > 0 ? devicePixelRatio : 1;
}

/** Rounds a value to the device pixel grid of the ratio (from dpr()). */
function snap(value, ratio) {
    var r = ratio > 0 ? ratio : 1;
    return Math.round(value * r) / r;
}
