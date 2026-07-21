# Flutter Dev Environment with Containerized OpenClaw

Date: 2026-07-21
Status: Approved

## Purpose

Give this Flutter project a remotely-controllable coding agent (OpenClaw) reachable via
Telegram, while keeping the agent's full read/write/execute access confined to a single
container instead of the host machine.

## Non-goals

- Remote *viewing* of the running Flutter web app from outside the local network (e.g. via
  a tunnel/reverse proxy). Out of scope for now — Telegram is the only remote access path,
  and Telegram's own servers relay chat traffic, so no inbound port exposure is needed for
  that.
- Android/iOS/desktop build targets. The sandbox ships the Flutter SDK configured for the
  **web** target only, to keep the image small and setup fast. APK builds continue to happen
  on the host via a normally-installed Flutter SDK, using the same repo checkout — the
  container is just an additional consumer of the same files, not a replacement for the host
  toolchain.

## Architecture

A single long-lived Docker container is the entire trust boundary for OpenClaw. It runs the
full OpenClaw gateway process itself (not just its tool calls) plus a Flutter SDK layer, all
as the image's non-root user. No OpenClaw process, config, or credentials live on the host —
only Docker is required there.

This intentionally differs from OpenClaw's built-in "gateway on host, sandbox per tool-call"
model. That model keeps the gateway process on the host and only routes individual tool
executions (`exec`, `read`, `write`, etc.) into ephemeral per-session Docker containers. It
works, but it means the gateway process itself — and anything that could compromise it — still
runs on the host. Collapsing gateway + tool execution into one container gives a single,
easier-to-reason-about boundary: whatever OpenClaw can reach is defined entirely by what's
bind-mounted into that one container.

This mirrors a working pattern already in use in `gizra/drupal-starter` (branch
`agent-balagan`), which runs OpenClaw the same way inside a DDEV service. This design adapts
that pattern for a plain (non-DDEV) Flutter project.

## Components

### `Dockerfile`

- `FROM ghcr.io/openclaw/openclaw:latest`
- Adds the Flutter SDK, configured for the web build target only (no Android SDK, no desktop
  toolchains)
- Stays on the base image's non-root user (`node`); UID should be verified to be 1000 so
  files the agent creates match the host user's ownership, avoiding permission friction when
  editing the same files from the host

### `docker-compose.yaml`

Single `openclaw` service with:

- `.:/workspace` (repo root, read-write) — the project the agent edits, builds, and tests
- `./openclaw/data:/home/node/.openclaw` (read-write, gitignored) — persistent OpenClaw
  config, Telegram channel pairing, gateway token; survives container recreation
- `${HOME}/.claude:/home/node/.claude` (read-write) — reuses the host's Claude Code
  subscription auth so OpenClaw runs against Claude Pro rather than metered API billing.
  This is the one deliberate credential exposure into the container, matching the tradeoff
  already accepted in the `drupal-starter` branch this design is based on.
- Normal container network egress (no restriction) — needed for `flutter pub get` / package
  fetches. The trust boundary is the container as a whole, not the network, so there's no
  separate egress-hardening step here.

### `entrypoint.sh`

On first run:
- Installs the Claude Code CLI into the persistent data dir (`/home/node/.openclaw/claude-cli`),
  cached across restarts
- Generates a gateway auth token if one doesn't already exist, and prints it once

Every run:
- `exec node openclaw.mjs gateway --allow-unconfigured --bind lan` — `--bind lan` (rather than
  loopback-only) is required for Docker's bridge networking to reach the gateway from other
  containers/CLI invocations

### `.githooks/pre-commit`

Blocks `git commit` to `main`/`master` from inside the container. Cheap insurance against the
agent pushing directly to the main branch, even by mistake. Wired via
`core.hookspath=.githooks` set as a container-local git config (not the host's).

### Telegram pairing

No standalone host CLI wrapper (this isn't a DDEV project, so there's no `ddev <command>`
convenience layer). Pairing and other OpenClaw CLI commands run directly via:

```bash
docker compose exec openclaw node openclaw.mjs channels add --channel telegram --token "<token>"
```

## Data flow

Telegram message → OpenClaw gateway (running inside the container) → agent reasons and calls
tools → tools execute directly in that same container against `/workspace` → command
output/results are relayed back through the gateway → reply sent back via Telegram.

## Security posture

- Single boundary: the container. No Docker socket mount, no nested sandbox-within-sandbox.
- Blast radius of a compromised agent is limited to what's bind-mounted: this repo (rw) and
  `~/.claude` (rw, for subscription auth).
- No other host paths, secrets, or services are reachable from the container.
- The pre-commit hook stops accidental direct commits to the main branch, but is not a
  security control against a deliberately malicious agent (it could edit `.githooks/`
  itself) — its purpose is guarding against mistakes during normal agent operation, not
  hardening against adversarial misuse.

## Verification plan

1. `docker compose up -d` and confirm the gateway starts and reports healthy.
2. Pair the Telegram channel using the command above.
3. From Telegram, ask the agent to run `flutter --version` and `flutter analyze` in
   `/workspace`; confirm output round-trips correctly through Telegram.
4. From Telegram, ask the agent to attempt `git commit` on `main`; confirm the pre-commit
   hook blocks it.
5. Confirm files created by the agent (e.g. via `flutter analyze` cache, `.dart_tool/`) are
   owned by the host user when viewed from the host shell (UID alignment check).
