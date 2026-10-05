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
});

test("time left uses the shared duration text", () => {
    const now = new Date(2026, 8, 30, 12);
    assert.equal(format.timeLeft(new Date(now.getTime() + 7500 * 1000), now), "2H 05M");
    assert.equal(format.timeLeft(new Date(now.getTime() + (3 * 86400 + 4 * 3600) * 1000), now), "3D 4H");
    assert.equal(format.timeLeft(new Date(now.getTime() - 1), now), "--");
    assert.equal(format.timeLeft(null, now), "--");
});
