.pragma library
.import "CalendarQueries.js" as Queries
.import "CalendarItems.js" as Items

// A page change shows two month pages, and each page reads three months (six).
// The month of the selected day and one spare month keep a far page change from evicting a shown month.
var MONTH_CACHE_LIMIT = 8;

/** Encodes a year and a month from 1 to 12 as a cache key. */
function monthId(year, month) {
    return year * 12 + month;
}

/** Decodes a cache key, keeping December in its original year. */
function monthFromId(id) {
    var year = Math.floor((id - 1) / 12);
    return { year: year, month: id - year * 12 };
}

/** A full rebuild for imports, outside file changes and calendar-wide settings. */
function createMonthCache(calendars) {
    return { projection: Queries.projectStoredCalendars(calendars), days: {}, order: [], builds: 0 };
}

/** View-ready month results. The month asked for longest ago leaves first when MONTH_CACHE_LIMIT is passed. */
function cachedItemsInMonth(cache, year, month) {
    var id = monthId(year, month);
    if (cache.days[id]) {
        var at = cache.order.indexOf(id);
        if (at !== cache.order.length - 1) {
            cache.order.splice(at, 1);
            cache.order.push(id);
        }
        return cache.days[id];
    }
    var days = Queries.storedItemsInMonth(cache.projection, year, month);
    for (var day in days) days[day] = days[day].map(Items.shownItem);
    cache.days[id] = days;
    cache.builds++;
    cache.order.push(id);
    if (cache.order.length > MONTH_CACHE_LIMIT) delete cache.days[cache.order.shift()];
    return days;
}

/**
 * Shows new calendar details (update time, error text) for one subscription whose records did not change.
 * Cached months stay. The caller must use this only when the records are the same.
 */
function refreshCalendarRow(cache, calendar) {
    var row = Queries.projectStoredCalendars([calendar]).calendars[0];
    var rows = cache.projection.calendars.map(function (old) { return old.id === calendar.id ? row : old; });
    cache.projection = { calendars: rows, sources: cache.projection.sources,
        names: cache.projection.names, reminders: cache.projection.reminders };
}

/** Month inputs for only the edited UIDs, with the calendar's colors applied. */
function changedItems(projection, calendarId, uids) {
    var source = projection.sources.find(function (s) { return s.id === calendarId; });
    var sources = [];
    if (source) {
        var selected = (source.items || source.records).filter(function (item) { return uids.indexOf(item.uid) >= 0; });
        sources.push(source.items ? { id: source.id, items: selected } :
            { id: source.id, color: source.color, colorOverrides: source.colorOverrides, records: selected });
    }
    return { sources: sources, names: projection.names };
}

/** Compare old and new occurrences only in cached months, including repeat rules and spans. */
function editMonthCache(cache, calendar, uids) {
    var projection = Queries.updateStoredCalendar(cache.projection, calendar);
    var before = changedItems(cache.projection, calendar.id, uids);
    var after = changedItems(projection, calendar.id, uids);
    cache.order = cache.order.filter(function (id) {
        var month = monthFromId(id);
        var oldDays = Queries.storedItemsInMonth(before, month.year, month.month);
        var newDays = Queries.storedItemsInMonth(after, month.year, month.month);
        if (JSON.stringify(oldDays) === JSON.stringify(newDays)) return true;
        delete cache.days[id];
        return false;
    });
    cache.projection = projection;
}
