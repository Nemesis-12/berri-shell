.pragma library
.import "CalendarItems.js" as Items
.import "IcsText.js" as Text
.import "IcsZones.js" as Zones
.import "IcsRead.js" as Read
.import "IcsWrite.js" as Write

/**
 * Reads and writes calendar text while keeping unknown fields and source dates.
 * The work sits in IcsText (syntax), IcsZones (time zones), IcsRead and IcsWrite;
 * this file is the one import that callers use.
 */

var calendarProduct = Write.calendarProduct;

function readCalendar(text, localZone) { return Read.readCalendar(text, localZone); }
function writeCalendar(cal, localZone) { return Write.writeCalendar(cal, localZone); }
function itemLines(item, localZone) { return Write.itemLines(item, localZone); }
function emptyCalendar() { return Read.emptyCalendar(); }
function expandCompactItem(record) { return Read.expandCompactItem(record); }
function foldLine(line) { return Text.foldLine(line); }
function unescapeText(text) { return Text.unescapeText(text); }
function zoneClock(ms, zone, localZone) { return Zones.zoneClock(ms, zone, localZone); }
