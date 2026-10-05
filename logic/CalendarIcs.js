.pragma library
.import "CalendarFormat.js" as Format
.import "CalendarItems.js" as Items
.import "CalendarQueries.js" as Queries
.import "CalendarMonths.js" as Months

/*
 * iCalendar (RFC 5545) subset used by berri's calendar. Pure functions, no QML.
 *
 * This file lists only the names that QML calls. Tests import the module they test
 * (CalendarFormat.js, CalendarItems.js, CalendarQueries.js, CalendarMonths.js).
 *
 * Calendar shape:  { prodid, raw: [line], rawComponents: [[line]], items: [Item] }
 *
 * Item shape (all dates "YYYY-MM-DD", all times "HH:MM", local display time):
 *   uid, kind ("event" | "task" | "reminder"), title,
 *   date, time (null = all-day / no time), end (end time, events only),
 *   endDate (last day of a multi-day all-day event, else null),
 *   color (preset key "accent" | "blue" | "green" | "yellow" | "red" | "cyan" | "magenta" | "orange",
 *   or a custom "#rrggbb"; stored as X-BERRI-COLOR, "accent" is not written),
 *   repeat ("none" | "daily" | "weekly" | "monthly" | "yearly"), interval,
 *   byDay (weekly only, 0 = Sunday), monthWeekday (monthly only: { nth, day }, nth 1 to 5 or -1 for the last,
 *   day 0 = Sunday; from BYDAY=2TU), until, count,
 *   exdates (skipped occurrence dates), doneDates (occurrence dates ticked off),
 *   alarmMinutes (VALARM minutes before start, null = none), status, stamp,
 *   ruleRest (RRULE parts berri ignores, written back unchanged),
 *   zoned (repeating event with a named time zone: { date, time, length, offsets }, the first source clock,
 *   the length in minutes and the [first day, UTC offset in seconds] changes of that zone, so each
 *   occurrence follows the daylight-saving changes of the zone; null otherwise),
 *   changedOccurrences (RECURRENCE-ID components of a repeating event: { from, cancelled, title, date, time, end, endDate },
 *   from = the day the occurrence had, date null = not moved; the component also stays in rawComponents),
 *   raw (unknown property lines, kept as is), rawChildren (unknown nested components),
 *   sourceDates (imported DTSTART, DTEND/DUE, UNTIL and EXDATE source forms).
 *   This is the stored item. CalendarItems.js checks it when it is built (storedItem).
 *   A projected item is a copy with calendarId, readOnly and hasOwnColor (projectedItem).
 *   A shown item is a copy for QML with a pair key in uid and the file UID in sourceUid (shownItem).
 *
 * Occurrence shape (what day and month queries return):
 *   uid, kind, title, color, date (the day shown), occurrenceDate (start day of
 *   this occurrence, use it for setDone/remove/move), time, end, endDate,
 *   allDay, repeat, recurring, done, alarmMinutes, calendarId, readOnly,
 *   hasOwnColor, alsoIn (names of the other calendars that hold the same
 *   event, [] when none), alsoInIds (their ids).
 *   (calendarId, readOnly and hasOwnColor come from projectedItem.)
 *   Subscription detail items also include location from LOCATION.
 *
 * Duplicates: an event in several calendars shows once. Two entries of
 * DIFFERENT calendars are the same event when the uid is the same, or when
 * start (day and time) and title are the same (see titleKey). Entries of one
 * calendar are never merged. The kept copy is the one of the calendar that
 * comes first, unless another copy has its own color.
 *
 * Old berri files stored a tag in CATEGORIES (personal, work, health, home).
 * It is read as a color when X-BERRI-COLOR is missing and is not written back.
 * CATEGORIES from other apps stay as raw lines.
 *
 * Month numbers are 1 to 12 everywhere.
 * Known limits: unknown TZIDs keep their source clock for display until edited.
 * A zoned series follows its zone for ten years from its first day.
 * A moved occurrence without DTEND has no end time. Deleting a moved occurrence of an editable calendar
 * leaves its RECURRENCE-ID component in the file.
 * BYMONTHDAY, BYSETPOS, a BYDAY list with week numbers and other rule parts stay raw but are ignored.
 * A cancelled item (STATUS:CANCELLED) has no occurrences, also in an editable calendar.
 */

// Names for QML callers.

var toKey = Items.toKey;
var cleanColor = Items.cleanColor;
var itemKey = Items.itemKey;
var itemIdentity = Items.itemIdentity;
var itemIndex = Items.itemIndex;
var makeItem = Items.makeItem;
var applyChanges = Items.applyChanges;
var withDone = Items.withDone;
var withoutOccurrence = Items.withoutOccurrence;
var moveOccurrence = Items.moveOccurrence;
var snoozeReminder = Items.snoozeReminder;
var dueBetween = Items.dueBetween;
var nextDueMs = Items.nextDueMs;
var clearItemColors = Items.clearItemColors;
var projectedItem = Items.projectedItem;
var shownItem = Items.shownItem;

var readCalendar = Format.readCalendar;
var writeCalendar = Format.writeCalendar;
var emptyCalendar = Format.emptyCalendar;
var expandCompactItem = Format.expandCompactItem;

var countDuplicates = Queries.countDuplicates;
var countStoredDuplicates = Queries.countStoredDuplicates;
var calendarName = Queries.calendarName;
var looksLikeCalendar = Queries.looksLikeCalendar;
var feedUrl = Queries.feedUrl;
var linkHost = Queries.linkHost;
var shortHash = Queries.shortHash;
var newCalendarColor = Queries.newCalendarColor;
var withColorOverride = Queries.withColorOverride;
var pruneColorOverrides = Queries.pruneColorOverrides;
var pruneRecordColorOverrides = Queries.pruneRecordColorOverrides;
var curlError = Queries.curlError;

var createMonthCache = Months.createMonthCache;
var cachedItemsInMonth = Months.cachedItemsInMonth;
var editMonthCache = Months.editMonthCache;
