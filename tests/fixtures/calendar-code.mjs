import fs from "node:fs";
import vm from "node:vm";

// Read the calendar code and its QML imports into separate test contexts.
export function calendarCode() {
  const files = new Map();
  function readCode(path) {
    if (files.has(path.href)) return files.get(path.href);
    const source = fs.readFileSync(path, "utf8");
    const imports = {};
    for (const match of source.matchAll(/^\.import "([^"]+)" as (\w+)$/gm)) {
      imports[match[2]] = readCode(new URL(match[1], path));
    }
    const code = vm.createContext(imports);
    vm.runInContext(source.replace(/^\.(?:pragma|import).*$/gm, ""), code, { filename: path.pathname });
    files.set(path.href, code);
    return code;
  }
  return readCode(new URL("../../logic/CalendarIcs.js", import.meta.url));
}
