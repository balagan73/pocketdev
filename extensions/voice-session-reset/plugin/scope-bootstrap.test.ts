// extensions/voice-session-reset/plugin/scope-bootstrap.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { bootstrapOperatorAdminScope, extractRequestId } from "./scope-bootstrap.ts";

const SCOPE_ERROR =
  "gateway connect failed: GatewayClientRequestError: scope upgrade pending approval " +
  "(requestId: 8cfa3407-dbfa-4bbb-a145-3dce789188ab)";

// Simulates the Gateway not listening yet — a plain connection failure with
// no scope-upgrade request in it. This is exactly what the old install.sh
// bootstrap hit, and what made it give up on the first attempt.
const NOT_READY_ERROR = "connect ECONNREFUSED 127.0.0.1:8787";

type Call = string[];

function makeHarness(responses: Array<{ code: number; stdout?: string; stderr?: string }>) {
  const calls: Call[] = [];
  const sleeps: number[] = [];
  const logs: { level: string; message: string }[] = [];
  let i = 0;

  const runCommand = async (args: string[]) => {
    calls.push(args);
    // Cleanup delete always succeeds and is not part of the scripted responses.
    if (args[2] === "sessions.delete") return { code: 0 };
    if (args[0] === "devices") return { code: 0 };
    const response = responses[i] ?? { code: 0 };
    i += 1;
    return response;
  };

  const logger = {
    info: (message: string) => logs.push({ level: "info", message }),
    warn: (message: string) => logs.push({ level: "warn", message }),
  };

  const sleep = async (ms: number) => {
    sleeps.push(ms);
  };

  return { calls, sleeps, logs, runCommand, logger, sleep };
}

test("extractRequestId pulls the id out of the real error format", () => {
  assert.equal(extractRequestId(SCOPE_ERROR), "8cfa3407-dbfa-4bbb-a145-3dce789188ab");
});

test("extractRequestId returns null when there is no request id", () => {
  assert.equal(extractRequestId(NOT_READY_ERROR), null);
  assert.equal(extractRequestId(""), null);
});

test("bootstrap: already-granted succeeds on first attempt without approving", async () => {
  const h = makeHarness([{ code: 0 }]);
  await bootstrapOperatorAdminScope(h.runCommand, h.logger, h.sleep);

  // Exactly two calls: the reset attempt, then the cleanup delete.
  assert.equal(h.calls.length, 2);
  assert.equal(h.calls[0][2], "sessions.reset");
  assert.equal(h.calls[1][2], "sessions.delete");
  assert.ok(!h.calls.some((c) => c[0] === "devices"), "must not call devices approve");
  assert.deepEqual(h.sleeps, [], "must not sleep when it succeeds immediately");
  assert.equal(h.logs.length, 1);
  assert.equal(h.logs[0].level, "info");
  assert.match(h.logs[0].message, /bootstrap succeeded/);
});

test("bootstrap: approves the scope request then succeeds", async () => {
  const h = makeHarness([{ code: 1, stderr: SCOPE_ERROR }, { code: 0 }]);
  await bootstrapOperatorAdminScope(h.runCommand, h.logger, h.sleep);

  const approve = h.calls.find((c) => c[0] === "devices");
  assert.ok(approve, "should have called devices approve");
  assert.deepEqual(approve, ["devices", "approve", "8cfa3407-dbfa-4bbb-a145-3dce789188ab"]);
  // Retries immediately after approving — no backoff needed for a real
  // scope rejection, only for "not ready yet" failures.
  assert.deepEqual(h.sleeps, []);
  assert.equal(h.logs[0].level, "info");
  assert.match(h.logs[0].message, /bootstrap succeeded/);
});

test("bootstrap: reads the request id from stdout as well as stderr", async () => {
  const h = makeHarness([{ code: 1, stdout: SCOPE_ERROR }, { code: 0 }]);
  await bootstrapOperatorAdminScope(h.runCommand, h.logger, h.sleep);

  const approve = h.calls.find((c) => c[0] === "devices");
  assert.deepEqual(approve, ["devices", "approve", "8cfa3407-dbfa-4bbb-a145-3dce789188ab"]);
});

test("bootstrap: warns after exhausting retries when the Gateway never comes up", async () => {
  const h = makeHarness(Array.from({ length: 6 }, () => ({ code: 1, stderr: NOT_READY_ERROR })));
  await bootstrapOperatorAdminScope(h.runCommand, h.logger, h.sleep);

  const resets = h.calls.filter((c) => c[2] === "sessions.reset");
  assert.equal(resets.length, 6, "should try MAX_ATTEMPTS times");
  // Sleeps between attempts, but not after the final one.
  assert.deepEqual(h.sleeps, [1500, 1500, 1500, 1500, 1500]);
  assert.equal(h.logs.length, 1);
  assert.equal(h.logs[0].level, "warn");
  assert.match(h.logs[0].message, /did not complete after retries/);
});

test("bootstrap: cleans up the bootstrap session on success and on failure", async () => {
  const ok = makeHarness([{ code: 0 }]);
  await bootstrapOperatorAdminScope(ok.runCommand, ok.logger, ok.sleep);
  assert.ok(
    ok.calls.some((c) => c[2] === "sessions.delete"),
    "cleanup must run after success",
  );

  const bad = makeHarness(Array.from({ length: 6 }, () => ({ code: 1, stderr: NOT_READY_ERROR })));
  await bootstrapOperatorAdminScope(bad.runCommand, bad.logger, bad.sleep);
  assert.ok(
    bad.calls.some((c) => c[2] === "sessions.delete"),
    "cleanup must run after failure too",
  );
});
