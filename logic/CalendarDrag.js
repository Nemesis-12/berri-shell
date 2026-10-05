.pragma library

/** How far (in pixels) the pointer must move from the press point before a calendar item drag starts. */
var threshold = 5;

/** True when a press moved far enough to be a drag: dx and dy are the pointer offset from the press point. */
function pastThreshold(dx, dy) {
    return Math.hypot(dx, dy) >= threshold;
}
