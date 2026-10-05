.pragma library

// Counts how many owners ask for the same shared thing. A thing (for example
// a Bluetooth adapter) stays on until the last owner lets go.

/** Returns an empty count table. Pass it to acquire() and release(). */
function create() {
    return { counts: new Map() };
}

/** One more owner asks for `key`. Returns the new count. */
function acquire(table, key) {
    var next = (table.counts.get(key) || 0) + 1;
    table.counts.set(key, next);
    return next;
}

/** One owner lets go of `key`. The count never goes below zero. Returns the new count. */
function release(table, key) {
    var next = Math.max(0, (table.counts.get(key) || 0) - 1);
    if (next === 0) table.counts.delete(key);
    else table.counts.set(key, next);
    return next;
}
