# Voice-Triggered Discord Session Reset

Date: 2026-08-16
Status: Approved
Issue: https://github.com/balagan73/pocketdev/issues/2

## Purpose

Let a user reset the Discord voice session's context by voice — saying something like
"start new session" — with a confirmation step, mirroring the "start new chat" option
already available in text channels. Today there is no voice-triggered way to do this;
the only existing tooling (`scripts/request-restart.sh`,
`scripts/start-new-discord-voice-session.sh`, `scripts/watch-restart.sh`) does it by
deleting the session's `sessions.json` entry and restarting the whole container, which
is slower and heavier than necessary.

## Non-goals

- Restarting the Gateway or container. OpenClaw resets a session in place without
  either, and that's the mechanism this design uses.
- Building a general-purpose voice command framework. This is one specific trigger
  phrase → confirm → reset flow.
- Detecting whether the inbound message came specifically from voice transcription vs.
  typed text in the same Discord channel session. Both share one session per channel
  (confirmed via `sessions.list`), and text already has `/new`, so the trigger firing on
  typed text too is harmless, not a regression.

## Background: how this was arrived at

Investigated (see issue comments for full detail) and ruled out two other mechanisms
before landing here:

- **The agent's own `sessions` tool** explicitly rejects resetting or deleting "the
  session currently running the tool" — the agent can't reset itself mid-conversation.
- **A plain `SKILL.md` skill** can only dispatch to *existing* tools via
  `command-dispatch: tool`, so it inherits the same restriction.
- **Importing the internal reset function directly** (`performGatewaySessionReset`,
  which both `/reset` and the `sessions.reset` RPC call under the hood) was considered
  and rejected — it isn't exported anywhere in `openclaw/plugin-sdk`, so using it would
  mean reaching past the documented SDK surface and silently bypassing the scope check
  the RPC path enforces on purpose.

The path that works, and is what this design builds: the plugin hook `before_agent_run`
can block an agent turn and substitute a custom reply *before* the model runs — the
right primitive for a confirmation dialog — and the actual reset happens via the
properly scope-checked `sessions.reset` Gateway RPC, called through the CLI. This was
verified end-to-end against the running container: created a throwaway session, reset
it via `sessions.reset`, deleted it via `sessions.delete`, both succeeded.

## Architecture

A new OpenClaw plugin, `voice-session-reset`, installed locally (not via ClawHub) under
`extensions/voice-session-reset/`, alongside the existing `extensions/discord-voice/`
config-only extension. It registers one `before_agent_run` hook:

1. **Trigger detection.** For inbound Discord channel sessions, match `event.prompt`
   against a trigger-phrase regex (e.g. "start new session", "start a new session",
   "reset chat", "reset the session"), case-insensitive.
2. **No pending confirmation yet, trigger matched:** block the run with a reply asking
   to confirm ("Want to start a new session? Say yes to confirm."). Record pending
   state for that session key with a short TTL (~20s).
3. **Pending confirmation exists, next message on the same session:**
   - Affirmative match ("yes", "confirm", "do it", etc.) → call the reset (below),
     block the run with a short confirmation reply ("Starting fresh."), clear pending
     state.
   - Negative or anything else → clear pending state, block with "Okay, keeping this
     session," so the ambiguous utterance doesn't get sent to the model as if it were
     real conversation content.
   - Expired TTL → treat as if no pending state existed; fall through to normal
     trigger-phrase detection on the new message instead.
4. **No trigger, no pending state:** hook returns nothing; the run proceeds normally.
   This is the common case and must add negligible overhead (a couple of regex tests
   per turn).

**Reset execution:** shell out via `api.runtime.system.runCommandWithTimeout(...)` to:

```bash
openclaw gateway call sessions.reset --json --params '{"key":"<sessionKey>","reason":"new"}'
```

`reason: "new"` mirrors `/new` semantics (archive + fresh) rather than `/reset`'s
in-place reset, matching the issue's "start with a fresh context" intent — confirmed by
reading the `sessions.reset` handler source, which branches on this same `reason` field
for both RPC and typed-command paths. The exact CLI invocation (binary path, whether
`openclaw` is on `PATH` inside the container vs. needing `node openclaw.mjs`) gets
confirmed as the first implementation step, not guessed here.

**State tracking:** a plain in-memory `Map<sessionKey, { expiresAt: number }>` inside
the plugin module. This repo runs a single Gateway process in a single container (see
`docs/superpowers/specs/2026-07-21-flutter-openclaw-container-design.md`), so
in-memory, non-persisted state is sufficient — no need for `api.runtime.state`'s
SQLite-backed store or session extensions.

## Components

### `extensions/voice-session-reset/plugin/package.json`

Declares the plugin entry (`openclaw.extensions: ["./index.ts"]`); no build step needed
since OpenClaw loads plugin TypeScript entries directly (it ships `jiti` as a runtime
TS loader).

### `extensions/voice-session-reset/plugin/openclaw.plugin.json`

Manifest: `id: "voice-session-reset"`, `activation.onStartup: true`. No
`contracts.tools` entry needed — this plugin registers a hook, not a tool.

### `extensions/voice-session-reset/plugin/index.ts`

The `before_agent_run` hook described above, using `definePluginEntry`.

### `extensions/voice-session-reset/install.sh`

Runs at container start (same pattern as `extensions/discord-voice/install.sh`):

1. `openclaw plugins install /pocket-dev/extensions/voice-session-reset/plugin` if not
   already installed.
2. `openclaw config patch --stdin` to set
   `plugins.entries.voice-session-reset.hooks.allowConversationAccess: true` — required
   for any non-bundled plugin using `before_agent_run` (a "raw conversation" hook per
   the plugin hooks reference).

### `.openclaw/README.md`

New section documenting the one-time manual setup this already required: granting the
in-container CLI device `operator.admin` scope via `openclaw devices approve
<requestId>` (surfaced by the first `sessions.reset` call attempt), alongside the
existing gh-auth/Discord-pairing one-time steps. Note that this grant is stored in
`.openclaw/data/identity/device.json` (bind-mounted from the host repo), so it survives
both `docker compose restart` and rebuilds.

### `scripts/request-restart.sh`, `scripts/start-new-discord-voice-session.sh`, `scripts/watch-restart.sh`

Removed. These implemented the heavier docker-restart approach this design replaces.

## Error handling / edge cases

- **RPC call fails** (Gateway unreachable, scope not granted, etc.): reply with a
  plain-language failure ("Couldn't reset the session, sorry — try again in a bit") and
  do not silently swallow the error; log it via `api.logger.error(...)`.
- **Trigger phrase appears mid-sentence in unrelated conversation** (e.g. "I want to
  start new session planning for the app"): accepted false-positive risk, mitigated by
  the confirmation step — worst case is one extra confirm/deny exchange, not an
  accidental reset.
- **Two trigger phrases in quick succession / overlapping runs:** the TTL-scoped
  `Map` is keyed per session, so a second trigger before the first confirms just resets
  the TTL rather than creating conflicting state.

## Security posture

- The reset call goes through OpenClaw's own scope-checked `sessions.reset` RPC, not an
  unexported internal function — the plugin cannot do anything the CLI device's
  approved scopes don't already allow.
- Granting `operator.admin` to the CLI device is scoped to this container only (bind
  mount, not exposed externally) and was an explicit, deliberate step, not something
  the plugin or its install script does automatically.
- No new network exposure, no new secrets. The plugin's only external action is a
  loopback call to the Gateway already running in the same container.

## Verification plan

1. `openclaw plugins inspect voice-session-reset --runtime --json` confirms the plugin
   loaded and the hook registered.
2. In the Discord voice channel: say the trigger phrase, confirm the bot asks for
   confirmation via TTS, say "yes," confirm the bot acknowledges and the session is
   fresh (e.g. it no longer recalls something said earlier in the conversation).
3. Repeat but decline the confirmation ("no") — confirm the session is *not* reset and
   normal conversation continues.
4. Say the trigger phrase and then wait past the TTL without responding — confirm a
   later unrelated message is treated normally, not as a stale confirmation.
5. Confirm `docker compose restart` and a full `docker compose up -d --build` both
   leave the `operator.admin` grant intact (`openclaw devices list` shows it in
   `approvedScopes` without re-prompting).
