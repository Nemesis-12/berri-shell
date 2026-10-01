.pragma library

/**
 * Pure notification list logic (ticket 50). No Quickshell types, so it runs
 * under node for tests. An item is
 *   { id, serverId, appName, appIcon, summary, body, time, urgency, read, snoozedUntil, actions }
 * with time and snoozedUntil in ms (snoozedUntil 0 means not snoozed).
 * The caller passes "now" so nothing here reads the clock.
 */

/** Newest first. Equal times keep the later-listed item first. */
function byNewest(a, b) {
    return b.time - a.time;
}

/** Items that are not snoozed at "now", newest first. */
function visible(all, now) {
    return all.filter(function (n) { return !(n.snoozedUntil > now); }).sort(byNewest);
}

/** Count of items that are snoozed at "now". */
function snoozedCount(all, now) {
    return all.filter(function (n) { return n.snoozedUntil > now; }).length;
}

/** The nearest future wake time of a snoozed item, or 0 when none. */
function nextWake(all, now) {
    var best = 0;
    all.forEach(function (n) {
        if (n.snoozedUntil > now && (best === 0 || n.snoozedUntil < best)) best = n.snoozedUntil;
    });
    return best;
}

/**
 * Groups by app from a newest-first list. Newest group first (by its newest
 * item); items inside a group stay newest first.
 * Returns [{ appName, appIcon, count, unread, items }].
 */
function groupByApp(list) {
    var groups = [];
    var byName = Object.create(null);
    list.forEach(function (n) {
        var g = byName[n.appName];
        if (!g) {
            g = { appName: n.appName, appIcon: n.appIcon, count: 0, unread: 0, items: [] };
            byName[n.appName] = g;
            groups.push(g);
        }
        if (!g.appIcon && n.appIcon) g.appIcon = n.appIcon;
        g.count++;
        if (!n.read) g.unread++;
        g.items.push(n);
    });
    return groups;
}

/** Filter column: [{ appName, appIcon, count }] sorted by app name. */
function appList(list) {
    return groupByApp(list)
        .map(function (g) { return { appName: g.appName, appIcon: g.appIcon, count: g.count }; })
        .sort(function (a, b) { return a.appName.localeCompare(b.appName); });
}

function unreadCount(list) {
    return list.filter(function (n) { return !n.read; }).length;
}

/**
 * Keeps at most "max" items. Drops the oldest read items first, then the
 * oldest unread ones. Snoozed items count like the others.
 */
function cap(all, max) {
    if (all.length <= max) return all;
    var drop = all.length - max;
    var oldestFirst = all.slice().sort(function (a, b) { return a.time - b.time; });
    var doomed = Object.create(null);
    oldestFirst.filter(function (n) { return n.read; }).slice(0, drop).forEach(function (n) {
        doomed[n.id] = true;
        drop--;
    });
    if (drop > 0) {
        oldestFirst.filter(function (n) { return !doomed[n.id]; }).slice(0, drop).forEach(function (n) {
            doomed[n.id] = true;
        });
    }
    return all.filter(function (n) { return !doomed[n.id]; });
}

/** Replaces the item with the same id, or adds the item when it is new. */
function upsert(all, item) {
    var found = false;
    var next = all.map(function (n) {
        if (n.id !== item.id) return n;
        found = true;
        return item;
    });
    if (!found) next.push(item);
    return next;
}

/** Finds a notification that Quickshell sent again after a reload. */
function findReloaded(all, serverId, appName, summary) {
    var matches = all.filter(function (n) {
        return n.serverId === serverId && n.appName === appName && n.summary === summary;
    });
    if (matches.length > 0) return matches.sort(byNewest)[0];
    // Older saved files have no server id. Use them only when the match is unique.
    matches = all.filter(function (n) {
        return n.serverId === undefined && n.appName === appName && n.summary === summary;
    });
    return matches.length === 1 ? matches[0] : null;
}

/** Keeps user state when the sender updates an existing notification. */
function keepState(old, item) {
    return Object.assign({}, item, {
        time: old.time, read: old.read, snoozedUntil: old.snoozedUntil
    });
}

/** Applies a change object to the item with this id. */
function patch(all, id, change) {
    return all.map(function (n) {
        return n.id === id ? Object.assign({}, n, change) : n;
    });
}

function remove(all, id) {
    return all.filter(function (n) { return n.id !== id; });
}

/** Removes the visible items of one app; snoozed ones stay (same as the mock). */
function removeApp(all, appName, now) {
    return all.filter(function (n) { return n.appName !== appName || n.snoozedUntil > now; });
}

/** Removes every visible item; snoozed ones stay. */
function removeVisible(all, now) {
    return all.filter(function (n) { return n.snoozedUntil > now; });
}

/** True when a new notification should raise the pop-up. Critical ones ignore do not disturb. */
function shouldAlert(urgency, dnd) {
    return !dnd || urgency === "critical";
}

/** Keep all waiting critical pop-ups and the newest other ones. Transient items are not in history. */
function queuePopup(queue, item, max) {
    var next = queue.concat([item]);
    var excess = next.filter(function (n) { return n.urgency !== "critical"; }).length - max;
    return next.filter(function (n) {
        if (n.urgency === "critical") return true;
        if (excess > 0) {
            excess--;
            return false;
        }
        return true;
    });
}

/** Reads the saved object. Bad or partial data gives safe defaults. */
function readSaved(values) {
    var out = { serverEnabled: false, dnd: false, items: [] };
    if (!values || typeof values !== "object") return out;
    out.serverEnabled = values.serverEnabled === true;
    out.dnd = values.dnd === true;
    if (Array.isArray(values.items)) {
        values.items.forEach(function (n) {
            if (!n || typeof n.id !== "string" || typeof n.time !== "number") return;
            out.items.push({
                id: n.id,
                serverId: typeof n.serverId === "number" ? n.serverId : undefined,
                appName: String(n.appName || ""),
                appIcon: String(n.appIcon || ""),
                summary: String(n.summary || ""),
                body: String(n.body || ""),
                time: n.time,
                urgency: n.urgency === "low" || n.urgency === "critical" ? n.urgency : "normal",
                read: n.read === true,
                snoozedUntil: typeof n.snoozedUntil === "number" ? n.snoozedUntil : 0,
                actions: []   // the sender is gone after a restart, so actions cannot work
            });
        });
    }
    return out;
}
