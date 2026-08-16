import { test } from "node:test";
import assert from "node:assert/strict";
import { matchesTriggerPhrase } from "./trigger.ts";

test("matches 'start new session'", () => {
  assert.equal(matchesTriggerPhrase("start new session"), true);
});

test("matches 'reset the session'", () => {
  assert.equal(matchesTriggerPhrase("please reset the session"), true);
});

test("matches 'restart the conversation'", () => {
  assert.equal(matchesTriggerPhrase("restart the conversation"), true);
});

test("matches 'wipe this chat'", () => {
  assert.equal(matchesTriggerPhrase("wipe this chat"), true);
});

test("matches 'forget this conversation'", () => {
  assert.equal(matchesTriggerPhrase("forget this conversation"), true);
});

test("is case-insensitive", () => {
  assert.equal(matchesTriggerPhrase("START NEW SESSION"), true);
});

test("does not match unrelated text", () => {
  assert.equal(matchesTriggerPhrase("what's the weather today"), false);
});

test("does not match empty string", () => {
  assert.equal(matchesTriggerPhrase(""), false);
});
