.pragma library

/**
 * Makes a ListModel (passed as `rows`) match a wanted list of entries with the
 * fewest changes, so a ListView's add, remove and move transitions play.
 * Entries are plain objects with a unique value in their key field (`key` by
 * default, or the name given as `idField`, for example "calId"). Existing
 * rows keep their place and only get new values for the fields that changed.
 */
function matchRows(rows, wanted, idField) {
    var k = idField || "key";
    var want = {};
    var i;
    for (i = 0; i < wanted.length; i++) want[wanted[i][k]] = true;

    for (i = rows.count - 1; i >= 0; i--) {
        if (!want[rows.get(i)[k]]) rows.remove(i);
    }

    for (i = 0; i < wanted.length; i++) {
        var entry = wanted[i];
        if (i < rows.count && rows.get(i)[k] === entry[k]) {
            replaceRow(rows, i, entry);
            continue;
        }
        var found = -1;
        for (var j = i + 1; j < rows.count; j++) {
            if (rows.get(j)[k] === entry[k]) { found = j; break; }
        }
        if (found >= 0) {
            rows.move(found, i, 1);
            replaceRow(rows, i, entry);
        } else {
            rows.insert(i, entry);
        }
    }
}

/** Sets only the fields of row `index` that differ from `entry`. */
function replaceRow(rows, index, entry) {
    var row = rows.get(index);
    for (var field in entry) {
        if (row[field] !== entry[field]) rows.setProperty(index, field, entry[field]);
    }
}
