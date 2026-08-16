import { test } from "node:test";
import assert from "node:assert/strict";
import { buildResetCommand } from "./reset-command.ts";

test("uses the openclaw binary", () => {
  const { cmd } = buildResetCommand("agent:main:discord:channel:123");
  assert.equal(cmd, "openclaw");
});

test("builds the correct gateway call arguments", () => {
  const { args } = buildResetCommand("agent:main:discord:channel:123");
  assert.deepEqual(args.slice(0, 4), ["gateway", "call", "sessions.reset", "--json"]);
  assert.equal(args[4], "--params");
});

test("params JSON contains the session key and reason=new", () => {
  const { args } = buildResetCommand("agent:main:discord:channel:123");
  const params = JSON.parse(args[5]);
  assert.deepEqual(params, { key: "agent:main:discord:channel:123", reason: "new" });
});

test("different session keys produce different params", () => {
  const { args } = buildResetCommand("agent:main:discord:channel:999");
  const params = JSON.parse(args[5]);
  assert.equal(params.key, "agent:main:discord:channel:999");
});
