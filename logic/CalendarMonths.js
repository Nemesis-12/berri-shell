.pragma library
.import "CalendarQueries.js" as Queries
.import "CalendarItems.js" as Items

var MONTH_CACHE_LIMIT = 3;

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
    return { projection: Queries.projectStoredCalendars(calendars), days: {}, order: [] };
}

/** View-ready month results, bounded by MONTH_CACHE_LIMIT in request order. */
function cachedItemsInMonth(cache, year, month) {
    var id = monthId(year, month);
    if (!cache.days[id]) {
        var days = Queries.storedItemsInMonth(cache.projection, year, month);
        for (var day in days) days[day] = days[day].map(Items.withItemIdentity);
        cache.days[id] = days;
        cache.order.push(id);
        if (cache.order.length > MONTH_CACHE_LIMIT) delete cache.days[cache.order.shift()];
    }
    return cache.days[id];
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
