// Run: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const times = vm.createContext({ Date });
vm.runInContext(fs.readFileSync(new URL("../logic/Times.js", import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, ""), times);
const format = vm.createContext({ Date, Times: times });
vm.runInContext(fs.readFileSync(new URL("../logic/CodeFormat.js", import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, "")
    .replace(/^\.import .*$/gm, ""), format);

test("commit age keeps its wording at each time boundary", () => {
    const now = new Date(2026, 8, 30, 12);
    for (const [minutes, expected] of [
        [-1, "0m ago"], [0, "0m ago"], [59, "59m ago"],
        [60, "1h ago"], [1439, "23h ago"], [1440, "yesterday"],
        [2879, "yesterday"], [2880, "2d ago"], [43199, "29d ago"]
    ]) {
        assert.equal(format.ago(new Date(now.getTime() - minutes * 60000), now), expected);
    }
    assert.equal(format.ago(new Date(2026, 7, 14, 12), now), "Aug 14");
});

test("rounded token and cost text picks the unit of the rounded value", () => {
    for (const [n, expected] of [
        [42, "42"], [7300, "7.3K"], [99949, "99.9K"], [99950, "100K"], [999499, "999K"],
        [999500, "1.00M"], [999999, "1.00M"], [1210000, "1.21M"], [99994999, "99.99M"],
        [99995000, "100M"], [250e6, "250M"]
    ]) {
        assert.equal(format.tokens(n), expected, String(n));
    }
    for (const [usd, expected] of [
        [12.4, "$12.40"], [999.99, "$999.99"], [999.996, "$1.0K"], [1234, "$1.2K"]
    ]) {
        assert.equal(format.cost(usd), expected, String(usd));
    }
    assert.equal(format.cost(null), "--");
});

test("time left uses the shared duration text", () => {
    const now = new Date(2026, 8, 30, 12);
    assert.equal(format.timeLeft(new Date(now.getTime() + 7500 * 1000), now), "2H 05M");
    assert.equal(format.timeLeft(new Date(now.getTime() + (3 * 86400 + 4 * 3600) * 1000), now), "3D 4H");
    assert.equal(format.timeLeft(new Date(now.getTime() - 1), now), "--");
    assert.equal(format.timeLeft(null, now), "--");
});

test("usage choices reject a misspelled source and keep missing readings distinct", () => {
    const usage = { claude: { today: { tokens: 34, cost: 0.5 } }, codex: {} };
    assert.deepEqual(format.usageFor(usage, "claude"), usage.claude);
    assert.deepEqual(format.usageFor(usage, "codex"), usage.codex);
    assert.throws(() => format.usageFor(usage, "cluade"), /Unknown usage source: cluade/);
});

test("heatmap hit testing clears the hover on gaps and padding", () => {
    const calendar = [["2026-10-04", 3]];
    assert.equal(format.heatmapIndexAt(calendar, 5, 5, 10, 2), 0);
    assert.equal(format.heatmapIndexAt(calendar, 11, 5, 10, 2), -1);
    assert.equal(format.heatmapIndexAt(calendar, 5, -1, 10, 2), -1);
    assert.equal(format.heatmapIndexAt(calendar, -100, 5, 10, 2), -1);
});

test("heatmap hit testing ignores a padding day and a point below the seventh row", () => {
    // Two weeks of days. The first day is a padding day with count -1.
    const calendar = Array.from({ length: 14 }, (_, i) => ["2026-10-0" + (i % 9 + 1), i === 0 ? -1 : 2]);
    assert.equal(format.heatmapIndexAt(calendar, 5, 5, 10, 2), -1);
    assert.equal(format.heatmapIndexAt(calendar, 5, 17, 10, 2), 1);
    assert.equal(format.heatmapIndexAt(calendar, 17, 5, 10, 2), 7);
    // Row 7 of column 0 would read index 7, which is the first day of column 1.
    assert.equal(format.heatmapIndexAt(calendar, 5, 7 * 12 + 5, 10, 2), -1);
});

test("a rate limit becomes unknown at its reset time or without a reset", () => {
    const now = new Date("2026-10-14T12:00:00Z");
    assert.equal(format.limitPercent(42, "2026-10-14T12:01:00Z", now, true), 42);
    assert.equal(format.limitPercent(42, "2026-10-14T12:00:00Z", now, true), -1);
    assert.equal(format.limitPercent(42, "", now, true), -1);
    assert.equal(format.limitPercent(-1, "2026-10-14T12:01:00Z", now, true), -1);
});

test("a rate limit of a source that is not known to be fresh is unknown", () => {
    const now = new Date("2026-10-14T12:00:00Z");
    assert.equal(format.limitPercent(42, "2026-10-14T12:01:00Z", now, false), -1);
    assert.equal(format.limitPercent(42, "2026-10-14T12:01:00Z", now, undefined), -1);
    assert.equal(format.limitPercent(42, "2026-10-14T12:01:00Z", now), -1);
});

test("usage source timestamps distinguish fresh, stale, missing and future answers", () => {
    const now = new Date("2026-10-14T12:00:00Z");
    assert.equal(format.sourceFresh("2026-10-14T11:59:00Z", now, 300000), true);
    assert.equal(format.sourceFresh("2026-10-14T11:54:59Z", now, 300000), false);
    assert.equal(format.sourceFresh("2026-10-14T12:01:00Z", now, 300000), false);
    assert.equal(format.sourceFresh("bad date", now, 300000), false);
    assert.equal(format.sourceFresh("", now, 300000), false);
});
