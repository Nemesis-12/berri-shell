.pragma library

/** True when both lists hold the same objects in the same order. A list model
 *  that gets an equal list again would destroy and rebuild its rows. */
function sameItems(a, b) {
    if (a.length !== b.length) return false;
    for (var i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) return false;
    }
    return true;
}
