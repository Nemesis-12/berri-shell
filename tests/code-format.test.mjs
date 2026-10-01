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
