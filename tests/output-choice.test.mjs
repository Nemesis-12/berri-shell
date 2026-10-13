import { test } from "node:test";
import assert from "node:assert/strict";
import { systemLogic } from "./fixtures/system-service.mjs";

const choice = systemLogic("OutputChoice");

test("the active output stays visible when there are more than three outputs", () => {
  const sinks = ["a", "b", "c", "d", "e"].map(name => ({ name }));
  const names = list => Array.from(list, sink => sink.name);
  assert.deepEqual(names(choice.shownOutputs(sinks, sinks[4], 3)), ["a", "b", "e"]);
  assert.deepEqual(names(choice.shownOutputs(sinks, sinks[3], 3)), ["a", "b", "d"]);
});

test("outputs keep their order when the active output is already shown or unknown", () => {
  const sinks = ["a", "b", "c", "d"].map(name => ({ name }));
  const names = list => Array.from(list, sink => sink.name);
  assert.deepEqual(names(choice.shownOutputs(sinks, sinks[1], 3)), ["a", "b", "c"]);
  assert.deepEqual(names(choice.shownOutputs(sinks, null, 3)), ["a", "b", "c"]);
  assert.deepEqual(names(choice.shownOutputs(sinks, { name: "stream" }, 3)), ["a", "b", "c"]);
  assert.deepEqual(names(choice.shownOutputs(sinks.slice(0, 2), sinks[1], 3)), ["a", "b"]);
});
