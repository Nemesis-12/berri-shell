.pragma library
.import "Times.js" as Times
.import "CalendarFormat.js" as Format
.import "CalendarItems.js" as Items
.import "CalendarQueries.js" as Queries

/*
 * iCalendar (RFC 5545) subset used by berri's calendar. Pure functions, no QML.
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
 *   byDay (weekly only, 0 = Sunday), until, count,
 *   exdates (skipped occurrence dates), doneDates (occurrence dates ticked off),
 *   alarmMinutes (VALARM minutes before start, null = none), status, stamp,
 *   ruleRest (RRULE parts berri ignores, written back unchanged),
 *   raw (unknown property lines, kept as is), rawChildren (unknown nested components),
 *   sourceDates (imported DTSTART, DTEND/DUE, UNTIL and EXDATE source forms).
 *   Calendar.qml gives view copies a pair key in uid and the file UID in sourceUid.
 *
 * Occurrence shape (what day and month queries return):
 *   uid, kind, title, color, date (the day shown), occurrenceDate (start day of
 *   this occurrence, use it for setDone/remove/move), time, end, endDate,
 *   allDay, repeat, recurring, done, alarmMinutes, calendarId, readOnly,
 *   hasOwnColor, alsoIn (names of the other calendars that hold the same
 *   event, [] when none), alsoInIds (their ids).
 *   (calendarId and readOnly come from mergeCalendars; items of several calendars.)
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
 * RECURRENCE-ID overrides, BYMONTHDAY and other rule parts stay raw but are ignored.
 */

// Keep one calendar import for QML callers and tests.
var FREQS = Format.repeatNames;
var WEEKDAYS = Format.weekdays;
var PRODID = Format.calendarProduct;
var COLOR_PRESETS = Items.itemColors;
var OLD_TAG_COLORS = Format.oldTagColors;

var dayNum = Times.dayNum;
var keyOfDayNum = Times.keyOfDayNum;

var utf8Length = Format.utf8Length;
var foldLine = Format.foldLine;
var unfold = Format.unfold;
var escapeText = Format.escapeText;
var splitUnescaped = Format.splitUnescaped;
var unescapeText = Format.unescapeText;
var parseLine = Format.parseLine;
var parseComponents = Format.parseComponents;
var utcClock = Format.utcClock;
var clockMs = Format.clockMs;
var zoneInstant = Format.zoneInstant;
var zoneClock = Format.zoneClock;
var parseDateValue = Format.parseDateValue;
var parseDateProperty = Format.parseDateProperty;
var parseRule = Format.parseRule;
var parseAlarm = Format.parseAlarm;
var parseItem = Format.parseItem;
var readCalendar = Format.readCalendar;
var readCompactCalendar = Format.readCompactCalendar;
var expandCompactItem = Format.expandCompactItem;
var icsDate = Format.icsDate;
var icsDateTime = Format.icsDateTime;
var dateProp = Format.dateProp;
var ruleText = Format.ruleText;
var itemLines = Format.itemLines;
var writeCalendar = Format.writeCalendar;
var emptyCalendar = Format.emptyCalendar;

var weekdayOf = Items.weekdayOf;
var daysInMonth = Items.daysInMonth;
var toKey = Items.toKey;
var addDays = Items.addDays;
var cleanColor = Items.cleanColor;
var itemKey = Items.itemKey;
var itemIdentity = Items.itemIdentity;
var itemIndex = Items.itemIndex;
var withItemIdentity = Items.withItemIdentity;
var newUid = Items.newUid;
var stampNow = Items.stampNow;
var normalize = Items.normalize;
var makeItem = Items.makeItem;
var applyChanges = Items.applyChanges;
var withDone = Items.withDone;
var withoutOccurrence = Items.withoutOccurrence;
var moveOccurrence = Items.moveOccurrence;
var snoozeTarget = Items.snoozeTarget;
var startDays = Items.startDays;
var occurrenceOf = Items.occurrenceOf;
var expand = Items.expand;
var dueBetween = Items.dueBetween;
var nextDueMs = Items.nextDueMs;
var clearItemColors = Items.clearItemColors;

var dayRank = Queries.dayRank;
var compareOccurrences = Queries.compareOccurrences;
var titleKey = Queries.titleKey;
var startTitleKey = Queries.startTitleKey;
var duplicateGroups = Queries.duplicateGroups;
var keptCopy = Queries.keptCopy;
var dropDuplicates = Queries.dropDuplicates;
var dropDuplicateOccurrences = Queries.dropDuplicateOccurrences;
var itemKeys = Queries.itemKeys;
var dropDuplicateItems = Queries.dropDuplicateItems;
var countDuplicates = Queries.countDuplicates;
var countStoredDuplicates = Queries.countStoredDuplicates;
var occurrencesByDay = Queries.occurrencesByDay;
var itemsOn = Queries.itemsOn;
var itemsInMonth = Queries.itemsInMonth;
var calendarName = Queries.calendarName;
var looksLikeCalendar = Queries.looksLikeCalendar;
var feedUrl = Queries.feedUrl;
var linkHost = Queries.linkHost;
var shortHash = Queries.shortHash;
var unusedColor = Queries.unusedColor;
var newCalendarColor = Queries.newCalendarColor;
var mergeCalendars = Queries.mergeCalendars;
var withColorOverride = Queries.withColorOverride;
var pruneColorOverrides = Queries.pruneColorOverrides;
var pruneRecordColorOverrides = Queries.pruneRecordColorOverrides;
var curlError = Queries.curlError;
var projectCalendars = Queries.projectCalendars;
var projectStoredCalendars = Queries.projectStoredCalendars;
var storedItemsInMonth = Queries.storedItemsInMonth;
