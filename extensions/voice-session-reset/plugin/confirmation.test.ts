// extensions/voice-session-reset/plugin/confirmation.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  classifyReply,
  matchesAffirmative,
  matchesNegative,
  PendingConfirmations,
} from "./confirmation.ts";

test("matchesAffirmative matches yes/confirm/go ahead", () => {
  assert.equal(matchesAffirmative("yes"), true);
  assert.equal(matchesAffirmative("yeah do it"), true);
  assert.equal(matchesAffirmative("confirmed"), true);
  assert.equal(matchesAffirmative("go ahead"), true);
});

test("matchesAffirmative does not match unrelated text", () => {
  assert.equal(matchesAffirmative("what time is it"), false);
});

test("matchesNegative matches no/cancel/nevermind", () => {
  assert.equal(matchesNegative("no"), true);
  assert.equal(matchesNegative("nope, cancel that"), true);
  assert.equal(matchesNegative("never mind"), true);
});

test("matchesNegative does not match unrelated text", () => {
  assert.equal(matchesNegative("what time is it"), false);
});

test("classifyReply: pure affirmative is yes", () => {
  assert.equal(classifyReply("yes"), "yes");
  assert.equal(classifyReply("yeah go ahead"), "yes");
  assert.equal(classifyReply("confirmed"), "yes");
  assert.equal(classifyReply("do it"), "yes");
});

test("classifyReply: pure negative is no", () => {
  assert.equal(classifyReply("no"), "no");
  assert.equal(classifyReply("nope"), "no");
  assert.equal(classifyReply("cancel"), "no");
  assert.equal(classifyReply("never mind"), "no");
});

test("classifyReply: negative takes precedence over overlapping affirmative", () => {
  // These match BOTH pattern sets — a naive affirmative-first check would
  // have reset the session on a spoken decline.
  assert.equal(classifyReply("no, don't do it"), "no");
  assert.equal(classifyReply("nope, do not do it"), "no");
  assert.equal(classifyReply("no way, go ahead and cancel"), "no");
});

test("classifyReply: unrelated or ambiguous text is no", () => {
  assert.equal(classifyReply("banana"), "no");
  assert.equal(classifyReply("what time is it"), "no");
  assert.equal(classifyReply(""), "no");
});

test("PendingConfirmations: not pending before start()", () => {
  const pending = new PendingConfirmations();
  assert.equal(pending.isPending("session-a"), false);
});

test("PendingConfirmations: pending immediately after start()", () => {
  const pending = new PendingConfirmations();
  pending.start("session-a");
  assert.equal(pending.isPending("session-a"), true);
});

test("PendingConfirmations: clear() removes pending state", () => {
  const pending = new PendingConfirmations();
  pending.start("session-a");
  pending.clear("session-a");
  assert.equal(pending.isPending("session-a"), false);
});

test("PendingConfirmations: expires after ttlMs using injected clock", () => {
  let currentTime = 1_000_000;
  const pending = new PendingConfirmations(30_000, () => currentTime);
  pending.start("session-a");
  currentTime += 29_999;
  assert.equal(pending.isPending("session-a"), true);
  currentTime += 2; // now 30_001ms after start, past the 30_000ms TTL
  assert.equal(pending.isPending("session-a"), false);
});

test("PendingConfirmations: sessions are tracked independently", () => {
  const pending = new PendingConfirmations();
  pending.start("session-a");
  assert.equal(pending.isPending("session-a"), true);
  assert.equal(pending.isPending("session-b"), false);
});
