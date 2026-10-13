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

/** Checks file structure before the tolerant reader can turn broken text into an empty calendar. */
function isCompleteCalendar(text) {
    var lines = Text.unfold((text || "").replace(/^\uFEFF/, "").replace(/[ \t\r\n]+$/, ""));
    var stack = [];
    var calendars = 0;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var upper = line.toUpperCase();
        if (upper.indexOf("BEGIN:") === 0) {
            var name = upper.slice(6);
            if (!/^[A-Z0-9-]+$/.test(name)) return false;
            if (!stack.length) {
                if (name !== "VCALENDAR" || calendars > 0) return false;
                calendars++;
            } else if (name === "VCALENDAR") return false;
            stack.push(name);
        } else if (upper.indexOf("END:") === 0) {
            if (!stack.length || stack.pop() !== upper.slice(4)) return false;
        } else {
            var property = Text.parseLine(line);
            if (!stack.length || line.indexOf(":") < 0 || !/^[A-Z0-9_-]+(?:\.[A-Z0-9_-]+)?$/.test(property.name)) return false;
        }
    }
    return calendars === 1 && stack.length === 0;
}
