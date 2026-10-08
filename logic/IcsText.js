.pragma library

/** iCalendar text syntax: folding, escaping, content lines and nested components. */

var weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

function utf8Length(str, index) {
    var c = str.charCodeAt(index);
    if (c < 0x80) return 1;
    if (c < 0x800) return 2;
    if (c >= 0xd800 && c <= 0xdbff) return 4; // surrogate pair, counted on the first half
    if (c >= 0xdc00 && c <= 0xdfff) return 0;
    return 3;
}

/** Folds one line to at most 75 octets per physical line, never inside a character. */
function foldLine(line) {
    // Fast path: an ASCII line of 75 characters or fewer is 75 octets or fewer.
    if (line.length <= 75 && !/[^\x00-\x7f]/.test(line)) return line;
    var out = [];
    var current = "";
    var bytes = 0;
    var limit = 75;
    for (var i = 0; i < line.length; i++) {
        var w = utf8Length(line, i);
        if (bytes + w > limit) {
            out.push(current);
            current = " ";
            bytes = 1;
            limit = 75;
        }
        current += line.charAt(i);
        bytes += w;
    }
    out.push(current);
    return out.join("\r\n");
}

/** Joins folded lines. Empty lines are dropped. */
function unfold(text) {
    var physical = text.split(/\r\n|\n|\r/);
    var lines = [];
    for (var i = 0; i < physical.length; i++) {
        var line = physical[i];
        var first = line.charAt(0);
        if ((first === " " || first === "\t") && lines.length > 0) lines[lines.length - 1] += line.substring(1);
        else if (line !== "") lines.push(line);
    }
    return lines;
}

function escapeText(text) {
    return String(text).replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r\n|\r|\n/g, "\\n");
}

function unescapeText(text) {
    return text.replace(/\\([\\;,nN])/g, function (all, c) {
        return (c === "n" || c === "N") ? "\n" : c;
    });
}

/** Splits a content line into { name, params, value, raw }. Quotes may hide ":" and ";". */
function parseLine(line) {
    var inQuote = false;
    var sep = -1;
    var cuts = [];
    for (var i = 0; i < line.length; i++) {
        var ch = line.charAt(i);
        if (ch === '"') inQuote = !inQuote;
        else if (!inQuote && ch === ";" && sep < 0) cuts.push(i);
        else if (!inQuote && ch === ":") { sep = i; break; }
    }
    if (sep < 0) return { name: line.toUpperCase(), params: {}, value: "", raw: line };
    var head = line.slice(0, sep);
    var pieces = [];
    var from = 0;
    for (var c = 0; c < cuts.length; c++) {
        pieces.push(line.slice(from, cuts[c]));
        from = cuts[c] + 1;
    }
    pieces.push(line.slice(from, sep));
    var params = {};
    for (var p = 1; p < pieces.length; p++) {
        var eq = pieces[p].indexOf("=");
        if (eq > 0) params[pieces[p].slice(0, eq).toUpperCase()] = pieces[p].slice(eq + 1).replace(/^"|"$/g, "");
    }
    return { name: pieces[0].toUpperCase(), params: params, value: line.slice(sep + 1), raw: line };
}

/** Turns unfolded lines into nested components: { name, props, children, lines }. */
function parseComponents(lines) {
    var roots = [];
    var stack = [];
    for (var i = 0; i < lines.length; i++) {
        var upper = lines[i].toUpperCase();
        if (upper.indexOf("BEGIN:") === 0) {
            var node = { name: upper.slice(6), props: [], children: [], start: i, lines: [] };
            if (stack.length) stack[stack.length - 1].children.push(node);
            else roots.push(node);
            stack.push(node);
        } else if (upper.indexOf("END:") === 0) {
            var done = stack.pop();
            if (done) done.lines = lines.slice(done.start, i + 1);
        } else if (stack.length) {
            stack[stack.length - 1].props.push(parseLine(lines[i]));
        }
    }
    return roots;
}
