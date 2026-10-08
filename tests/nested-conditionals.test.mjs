import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

/** Removes comments, strings and regex literals so only code operators stay. */
function stripLiterals(source) {
  let out = "";
  let i = 0;
  let last = ";";
  while (i < source.length) {
    const c = source[i];
    const next = source[i + 1];
    if (c === "/" && next === "/") { while (i < source.length && source[i] !== "\n") i++; continue; }
    if (c === "/" && next === "*") { i = source.indexOf("*/", i) + 2; continue; }
    if (c === '"' || c === "'" || c === "`") {
      i++;
      while (source[i] !== c) i += source[i] === "\\" ? 2 : 1;
      i++;
      out += "0";
      last = "0";
      continue;
    }
    if (c === "/" && /[(,=:\[!&|?{};]/.test(last)) {
      i++;
      let inClass = false;
      while (source[i] !== "/" || inClass) {
        if (source[i] === "\\") i++;
        else if (source[i] === "[") inClass = true;
        else if (source[i] === "]") inClass = false;
        i++;
      }
      i++;
      out += "0";
      last = "0";
      continue;
    }
    out += c;
    if (!/\s/.test(c)) last = c;
    i++;
  }
  return out;
}

/** Returns the 1-based lines where a conditional expression sits inside another one. */
export function nestedConditionalLines(source) {
  const code = stripLiterals(source);
  const open = [];
  const brackets = [];
  const found = [];
  let line = 1;
  for (let i = 0; i < code.length; i++) {
    const c = code[i];
    if (c === "\n") line++;
    else if ("([{".includes(c)) brackets.push(c);
    else if (")]}".includes(c)) {
      brackets.pop();
      while (open.length && open[open.length - 1].depth > brackets.length) open.pop();
    } else if (c === "," || c === ";") {
      while (open.length && open[open.length - 1].depth >= brackets.length) open.pop();
    } else if (c === "?" && code[i + 1] !== "." && code[i + 1] !== "?" && code[i - 1] !== "?") {
      if (open.length) found.push(line);
      open.push({ depth: brackets.length, colon: false });
    } else if (c === ":" && open.length) {
      const top = open[open.length - 1];
      if (top.depth === brackets.length && !top.colon) top.colon = true;
    }
  }
  return found;
}

test("the scan finds nested and chained conditionals", () => {
  assert.deepEqual(nestedConditionalLines("var a = b ? 1 : 2;\nvar c = d ? 1 : 2;"), []);
  assert.deepEqual(nestedConditionalLines("var a = b ? 1 : c ? 2 : 3;"), [1]);
  assert.deepEqual(nestedConditionalLines("var a = b ? (c ? 1 : 2) : 3;"), [1]);
  assert.deepEqual(nestedConditionalLines("f({\n x: a ? 1 : 2,\n y: b ? 1 : 2 });"), []);
  assert.deepEqual(nestedConditionalLines("var r = /a?b/.test(s) ? \"x?y\" : null; // a ? b ? c"), []);
});

test("draft field rules have no conditional inside another conditional", () => {
  const source = fs.readFileSync(new URL("../logic/CalendarDraft.js", import.meta.url), "utf8");
  assert.deepEqual(nestedConditionalLines(source), []);
});
