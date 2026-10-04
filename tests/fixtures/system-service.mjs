import fs from "node:fs";
import vm from "node:vm";

// Load the shipped parsers without QML's pragma for service boundary tests.
export function systemLogic(name) {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(new URL(`../../logic/${name}.js`, import.meta.url), "utf8")
    .replace(/^\.pragma library.*$/m, ""), context);
  return context;
}

// Execute the real service functions with file/process I/O supplied by each test.
export function systemService(name, state) {
  const source = fs.readFileSync(new URL(`../../services/${name}.qml`, import.meta.url), "utf8");
  const context = vm.createContext({ Readings: systemLogic("SystemReadings"),
    MemoryUse: systemLogic("MemoryUse"), ...state });
  context.root = context;
  for (const [, name, args, body] of source.matchAll(/^    function (\w+)\((.*?)\) \{([\s\S]*?)^    \}/gm))
    vm.runInContext(`function ${name}(${args}) {${body}\n}`, context);
  return context;
}
