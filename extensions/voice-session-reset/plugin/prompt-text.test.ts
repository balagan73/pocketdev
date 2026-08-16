import { test } from "node:test";
import assert from "node:assert/strict";
import { extractUserUtterance } from "./prompt-text.ts";

test("extracts the utterance after the voice transcript marker", () => {
  const prompt =
    'You are OpenClaw\'s Discord voice interface in a live voice channel.\n' +
    'Discord voice reply requirements:\n' +
    '- Do not reply with NO_REPLY unless no spoken response is appropriate.\n\n' +
    'Voice transcript from speaker "balagan73":\nYes.';
  assert.equal(extractUserUtterance(prompt), "Yes.");
});

test("is case-insensitive on the marker", () => {
  const prompt = 'VOICE TRANSCRIPT FROM SPEAKER "x":\nreset the session';
  assert.equal(extractUserUtterance(prompt), "reset the session");
});

test("falls back to the full trimmed text when there is no marker", () => {
  assert.equal(extractUserUtterance("  reset the session  "), "reset the session");
});

test("the boilerplate text itself no longer poisons a yes/no check", () => {
  const prompt =
    "Do not reply with NO_REPLY unless no spoken response is appropriate.\n\n" +
    'Voice transcript from speaker "balagan73":\nyes';
  const utterance = extractUserUtterance(prompt);
  assert.equal(utterance, "yes");
  assert.doesNotMatch(utterance, /\bno\b/i);
});
