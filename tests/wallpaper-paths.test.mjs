import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const source = fs.readFileSync(new URL("../logic/WallpaperPaths.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "");
const paths = vm.createContext({});
vm.runInContext(source, paths);

test("wallpaper file URLs encode path spaces and reserved characters", () => {
  assert.equal(paths.fileUrl("/tmp/wallpaper space #1.png"),
    "file:///tmp/wallpaper%20space%20%231.png");
});
