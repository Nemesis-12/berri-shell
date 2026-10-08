.pragma library
.import "CalendarItems.js" as Items
.import "IcsText.js" as Text
.import "IcsRead.js" as Read
.import "IcsWrite.js" as Write

/**
 * Reads and writes calendar text while keeping unknown fields and source dates.
 * The work sits in IcsText (syntax), IcsZones (time zones), IcsRead and IcsWrite;
 * this file is the one import that callers use.
 */

var readCalendar = Read.readCalendar;
var emptyCalendar = Read.emptyCalendar;
var expandCompactItem = Read.expandCompactItem;
var writeCalendar = Write.writeCalendar;
var unescapeText = Text.unescapeText;
