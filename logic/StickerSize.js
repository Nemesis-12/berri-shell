.pragma library

/**
 * Image size of the Home sticker. The cell is `width` x `height` logical
 * pixels on a screen with `scale` image pixels per logical pixel. The
 * display copy and the image decode both use this size, so the screen
 * shows one image pixel per device pixel. Returns whole pixels, at least 1.
 */
function pixelSize(width, height, scale) {
    return {
        width: Math.max(1, Math.round(width * scale)),
        height: Math.max(1, Math.round(height * scale))
    };
}

/** True when the cell has a size to draw (both sides above zero). */
function hasSize(width, height) {
    return width > 0 && height > 0;
}
