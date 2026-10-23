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

test("wallpaper file URLs encode percent signs, question marks and non-ASCII names", () => {
  assert.equal(paths.fileUrl("/tmp/100% real?.png"), "file:///tmp/100%25%20real%3F.png");
  assert.equal(paths.fileUrl("/tmp/Hintergrund-Bäume.jpg"), "file:///tmp/Hintergrund-B%C3%A4ume.jpg");
});
