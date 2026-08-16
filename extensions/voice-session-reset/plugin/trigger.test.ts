import { test } from "node:test";
import assert from "node:assert/strict";
import { matchesTriggerPhrase } from "./trigger.ts";

test("matches 'start new session'", () => {
  assert.equal(matchesTriggerPhrase("start new session"), true);
});

test("matches 'start a new session' inside a longer sentence", () => {
  assert.equal(matchesTriggerPhrase("hey can you start a new session please"), true);
});

test("matches 'reset chat'", () => {
  assert.equal(matchesTriggerPhrase("reset chat"), true);
});

test("matches 'reset the session'", () => {
  assert.equal(matchesTriggerPhrase("please reset the session"), true);
});

test("is case-insensitive", () => {
  assert.equal(matchesTriggerPhrase("START NEW SESSION"), true);
});

test("matches 'restart the session'", () => {
  assert.equal(matchesTriggerPhrase("restart the session"), true);
});

test("matches 'restart session' without 'the'", () => {
  assert.equal(matchesTriggerPhrase("please restart session"), true);
});

test("matches 'restart chat'", () => {
  assert.equal(matchesTriggerPhrase("restart chat"), true);
});

test("matches 'start the new session'", () => {
  assert.equal(matchesTriggerPhrase("start the new session"), true);
});

test("does not match unrelated text", () => {
  assert.equal(matchesTriggerPhrase("what's the weather today"), false);
});

test("does not match empty string", () => {
  assert.equal(matchesTriggerPhrase(""), false);
});
