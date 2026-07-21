# Flutter OpenClaw Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give this repo a Telegram-controllable OpenClaw agent whose entire process — gateway and tool execution alike — runs inside one Docker container with a Flutter (web-only) SDK, so the agent's reach never extends past that container.

**Architecture:** A single long-lived container, built `FROM ghcr.io/openclaw/openclaw:latest` with a Flutter SDK layer added, runs the OpenClaw gateway directly (no host-side OpenClaw process, no nested per-tool-call sandbox). `docker-compose.yml` bind-mounts this repo (rw) and the host's `~/.claude` (rw, for Claude Pro subscription auth) into the container; a persistent `.openclaw/data/` directory survives container recreation. A git hook wired only inside the container blocks commits to `main`/`master`.

**Tech Stack:** Docker, Docker Compose, `ghcr.io/openclaw/openclaw:latest` (Debian bookworm, Node 24, non-root `node` user UID 1000), Flutter SDK (stable channel, web target only), bash.

## Global Constraints

- Flutter SDK configured for the **web build target only** — no Android SDK, no desktop toolchains (per spec non-goals).
- The container is the entire trust boundary — no Docker socket mount, no additional sandbox-within-sandbox, no published ports (verification happens via `docker compose exec`, not host-exposed HTTP).
- Non-root `node` user, UID 1000 — confirmed to match the host user `balagan73` (UID 1000), so agent-created files need no ownership fixups when touched from the host.
- OpenClaw auth reuses the host's Claude Code subscription via a read-write bind mount of `~/.claude` — the one deliberate credential exposure into the container.
- `.githooks/pre-commit` blocks commits to `main`/`master`, wired via per-container `GIT_CONFIG_*` env vars so the host's own `.git/config` is never touched.
- Confirmed on this host: Docker 29.6.2, Docker Compose v5.3.1, host UID 1000, `git`/`curl` already present in the base image; `unzip`/`xz-utils` are not and must be installed.

---

### Task 1: Git-hook guard and repo scaffolding

**Files:**
- Create: `.githooks/pre-commit`
- Create: `.gitignore`
- Create: `.openclaw/data/.gitkeep`

**Interfaces:**
- Produces: `.githooks/pre-commit` (executable script, exit 1 on `main`/`master`, exit 0 otherwise) — consumed by Task 4's container wiring via `core.hookspath=.githooks`.
- Produces: `.openclaw/data/` as an existing, gitignored directory — consumed by Task 4's `./.openclaw/data:/home/node/.openclaw` volume mount.

- [ ] **Step 1: Write the pre-commit hook**

```bash
#!/bin/bash

# Get the current branch name
branch_name=$(git symbolic-ref --short HEAD 2>/dev/null)

# Define protected branches
protected_branches=("main" "master")

# Check if the current branch is protected
if [[ " ${protected_branches[@]} " =~ " ${branch_name} " ]]; then
  echo "Committing to '${branch_name}' is not allowed."
  exit 1
fi

exit 0
```

Save as `.githooks/pre-commit`.

- [ ] **Step 2: Make it executable**

```bash
chmod +x .githooks/pre-commit
```

- [ ] **Step 3: Verify it blocks the current branch (master)**

```bash
git symbolic-ref --short HEAD
bash .githooks/pre-commit; echo "exit: $?"
```

Expected: first command prints `master`; second prints `Committing to 'master' is not allowed.` and `exit: 1`.

- [ ] **Step 4: Verify it allows a non-protected branch**

This is a local-only, reversible git operation (no push, no history rewrite):

```bash
git checkout -b tmp-hook-test
bash .githooks/pre-commit; echo "exit: $?"
git checkout master
git branch -D tmp-hook-test
```

Expected: second line prints only `exit: 0` (no "not allowed" message) while on `tmp-hook-test`; the branch is then deleted, leaving no trace.

- [ ] **Step 5: Write `.gitignore`**

```
# OpenClaw persistent runtime data (config, Telegram pairing, gateway token, Claude CLI cache)
/.openclaw/data/*
!/.openclaw/data/.gitkeep
```

Save as `.gitignore`.

- [ ] **Step 6: Create the data directory placeholder**

```bash
mkdir -p .openclaw/data
touch .openclaw/data/.gitkeep
```

- [ ] **Step 7: Verify git status is clean and as expected**

```bash
git status
```

Expected: `.githooks/pre-commit`, `.gitignore`, and `.openclaw/data/.gitkeep` listed as new/untracked files; nothing else changed.

- [ ] **Step 8: Commit**

```bash
git add .githooks/pre-commit .gitignore .openclaw/data/.gitkeep
git commit -m "Add pre-commit branch guard and OpenClaw data scaffolding"
```

---

### Task 2: Dockerfile — OpenClaw base + Flutter SDK (web target only)

**Files:**
- Create: `.openclaw/Dockerfile`

**Interfaces:**
- Consumes: nothing from earlier tasks (independent of Task 1).
- Produces: image `flutterclaw-openclaw:dev` (dev tag for local testing) with `flutter` on `PATH` for the `node` user (UID 1000), web target enabled — consumed by Task 3 (entrypoint smoke test) and Task 4 (`docker-compose.yml` build).

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
FROM ghcr.io/openclaw/openclaw:latest

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends unzip xz-utils \
  && rm -rf /var/lib/apt/lists/*
USER node

ENV FLUTTER_HOME=/home/node/flutter
ENV PATH="$FLUTTER_HOME/bin:$PATH"

RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
  && flutter config --enable-web --no-analytics \
  && flutter precache --web

# Informational only — flutter doctor reports on Android/desktop/Chrome
# tooling we deliberately don't install; never fail the build on it.
RUN flutter doctor -v || true
```

Save as `.openclaw/Dockerfile`.

- [ ] **Step 2: Build the image**

```bash
docker build -t flutterclaw-openclaw:dev ./.openclaw
```

Expected: build completes successfully (ends with the image being tagged, no error exit).

- [ ] **Step 3: Verify Flutter is on PATH and on the stable channel**

```bash
docker run --rm flutterclaw-openclaw:dev flutter --version
```

Expected: output includes a line starting with `Flutter` and mentions `channel stable`.

- [ ] **Step 4: Verify the web target is enabled**

```bash
docker run --rm flutterclaw-openclaw:dev flutter config
```

Expected: printed settings include `enable-web: true`.

- [ ] **Step 5: Verify the container runs as the expected non-root UID**

```bash
docker run --rm flutterclaw-openclaw:dev id
```

Expected: `uid=1000(node) gid=1000(node) groups=1000(node)` — matches the host user `balagan73` (UID 1000).

- [ ] **Step 6: Commit**

```bash
git add .openclaw/Dockerfile
git commit -m "Add Flutter (web-only) layer on top of the OpenClaw base image"
```

---

### Task 3: entrypoint.sh

**Files:**
- Create: `.openclaw/entrypoint.sh`

**Interfaces:**
- Consumes: image `flutterclaw-openclaw:dev` from Task 2 (for the smoke test only).
- Produces: `.openclaw/entrypoint.sh`, invoked as the container's `entrypoint` — consumed by Task 4's `docker-compose.yml`. Writes `OPENCLAW_GATEWAY_TOKEN=<token>` to `$OPENCLAW_CONFIG_DIR/.env` (i.e. `/home/node/.openclaw/.env`) on first run — consumed by Task 4's health check and Task 5's pairing step.

- [ ] **Step 1: Write the entrypoint script**

```bash
#!/bin/bash
set -euo pipefail

# Avoid git "dubious ownership" errors against the bind-mounted /workspace repo.
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx /workspace; then
  git config --global --add safe.directory /workspace
fi

# Install Claude Code CLI into the persistent data dir on first run (cached across restarts).
CLAUDE_PREFIX="/home/node/.openclaw/claude-cli"
CLAUDE_BIN="$CLAUDE_PREFIX/bin/claude"
if [ ! -x "$CLAUDE_BIN" ]; then
  echo "Installing Claude Code CLI (first run — cached in openclaw data dir)..."
  npm install -g @anthropic-ai/claude-code --prefix "$CLAUDE_PREFIX" --quiet 2>&1 \
    && echo "Claude CLI installed." \
    || echo "Warning: Claude CLI install failed — claude-cli/* models unavailable"
fi
if [ -x "$CLAUDE_BIN" ]; then
  export PATH="$CLAUDE_PREFIX/bin:$PATH"
fi

# Generate a gateway auth token on first run and print it once.
OPENCLAW_DIR="/home/node/.openclaw"
OPENCLAW_ENV="$OPENCLAW_DIR/.env"
mkdir -p "$OPENCLAW_DIR"
if ! grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$OPENCLAW_ENV" 2>/dev/null; then
  TOKEN=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32) || true
  printf "OPENCLAW_GATEWAY_TOKEN=%s\n" "$TOKEN" >> "$OPENCLAW_ENV"
  echo "============================================================"
  echo "Generated gateway token: $TOKEN"
  echo "Run: docker compose exec openclaw node openclaw.mjs health --token $TOKEN"
  echo "============================================================"
fi

# If arguments were passed (docker compose exec/run <cmd>), run them directly.
# Otherwise start the gateway (docker compose up).
if [ $# -gt 0 ]; then
  exec "$@"
fi

# --bind lan is required for Docker's bridge networking; loopback-only won't be reachable.
exec node openclaw.mjs gateway --allow-unconfigured --bind lan
```

Save as `.openclaw/entrypoint.sh`.

- [ ] **Step 2: Make it executable**

```bash
chmod +x .openclaw/entrypoint.sh
```

- [ ] **Step 3: Syntax-check it**

```bash
bash -n .openclaw/entrypoint.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Smoke-test the passthrough and first-run logic in isolation**

This runs the entrypoint against Task 2's image without starting the real gateway, using a throwaway named volume so nothing persists:

```bash
docker volume create flutterclaw-oc-test-data
docker run --rm \
  -v "$(pwd)/.openclaw/entrypoint.sh:/oc-init/entrypoint.sh:ro" \
  -v flutterclaw-oc-test-data:/home/node/.openclaw \
  --entrypoint /bin/bash \
  flutterclaw-openclaw:dev /oc-init/entrypoint.sh echo "entrypoint smoke test ok"
```

Expected: logs show the Claude CLI install attempt, then the `Generated gateway token: ...` banner, then finally `entrypoint smoke test ok` as the last line — proving the `[ $# -gt 0 ]` passthrough branch ran `echo` instead of launching the gateway.

- [ ] **Step 5: Clean up the test volume**

```bash
docker volume rm flutterclaw-oc-test-data
```

- [ ] **Step 6: Commit**

```bash
git add .openclaw/entrypoint.sh
git commit -m "Add OpenClaw container entrypoint (Claude CLI install, gateway token, exec gateway)"
```

---

### Task 4: docker-compose.yml — wire the stack and bring it up

**Files:**
- Create: `docker-compose.yml`

**Interfaces:**
- Consumes: `.openclaw/Dockerfile` (Task 2), `.openclaw/entrypoint.sh` (Task 3), `.githooks/pre-commit` + `.openclaw/data/` (Task 1).
- Produces: a running `openclaw` service reachable via `docker compose exec openclaw ...` — consumed by Task 5 (Telegram pairing).

- [ ] **Step 1: Write docker-compose.yml**

```yaml
# OpenClaw runs as a single container: the full gateway process plus a
# Flutter SDK (web target only), giving it read/write/execute access
# scoped to this repo and nothing else on the host.
#
# First run:
#   docker compose up -d --build
#   docker compose logs openclaw   # copy the printed gateway token
#
# Pair Telegram:
#   docker compose exec openclaw node openclaw.mjs channels add --channel telegram --token "<bot-token>"

services:
  openclaw:
    build:
      context: ./.openclaw
      dockerfile: Dockerfile
    container_name: flutterclaw-openclaw
    restart: unless-stopped
    entrypoint: ["/bin/bash", "/oc-init/entrypoint.sh"]
    environment:
      - OPENCLAW_SKIP_ONBOARDING=true
      - OPENCLAW_CONFIG_DIR=/home/node/.openclaw
      - OPENCLAW_WORKSPACE_DIR=/workspace
      # Block commits to main/master from inside this container only.
      - GIT_CONFIG_COUNT=1
      - GIT_CONFIG_KEY_0=core.hookspath
      - GIT_CONFIG_VALUE_0=.githooks
    volumes:
      - .:/workspace
      - ./.openclaw/data:/home/node/.openclaw
      - ./.openclaw/entrypoint.sh:/oc-init/entrypoint.sh:ro
      - ${HOME}/.claude:/home/node/.claude
```

Save as `docker-compose.yml` at the repo root.

- [ ] **Step 2: Bring the stack up**

```bash
docker compose up -d --build
docker compose ps
```

Expected: `docker compose ps` shows the `openclaw` service with state `running`/`Up`.

- [ ] **Step 3: Read the generated gateway token from the logs**

```bash
docker compose logs openclaw | grep -A1 "Generated gateway token"
```

Expected: a line showing `Generated gateway token: <32-char alphanumeric string>`. (It's also saved at `.openclaw/data/.env` for reuse after restarts.)

- [ ] **Step 4: Verify the workspace mount**

```bash
docker compose exec openclaw ls /workspace
```

Expected: lists this repo's contents, including `docker-compose.yml`, `.openclaw`, `docs`, `.githooks`.

- [ ] **Step 5: Verify Flutter is reachable inside the running service**

```bash
docker compose exec openclaw flutter --version
```

Expected: same `Flutter`/`channel stable` output as Task 2 Step 3.

- [ ] **Step 6: Verify gateway health**

```bash
TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN .openclaw/data/.env | cut -d= -f2)
docker compose exec openclaw node openclaw.mjs health --token "$TOKEN"
```

Expected: a healthy/OK response with exit code 0.

- [ ] **Step 7: Verify the git-hook wiring is container-scoped**

```bash
docker compose exec openclaw bash -c 'cd /workspace && git config --get core.hookspath'
git config --get core.hookspath
```

Expected: the first command prints `.githooks`; the second (run on the host) prints nothing, confirming the host's own `.git/config` was never modified.

- [ ] **Step 8: Verify UID alignment end-to-end**

```bash
docker compose exec openclaw bash -c 'touch /workspace/.uid-test'
ls -ln .uid-test
rm .uid-test
```

Expected: `ls -ln` shows the file owned by UID `1000` — matching the host user `balagan73`, confirming no permission fixups are needed when editing agent-created files from the host.

- [ ] **Step 9: Commit**

```bash
git add docker-compose.yml
git commit -m "Add docker-compose.yml running OpenClaw + Flutter as a single container"
```

---

### Task 5: Telegram pairing and allowlist

**Files:**
- Modify (at runtime, not tracked in git): `.openclaw/data/openclaw.json` — created by OpenClaw itself on first channel pairing; this task edits it afterward. It lives under the gitignored `.openclaw/data/` path, so no repo commit results from this task unless noted in Step 6.

**Interfaces:**
- Consumes: the running `openclaw` service from Task 4.
- Produces: a paired Telegram channel — the end-to-end path the whole plan exists to deliver.

- [ ] **Step 1: Create a Telegram bot**

Message [@BotFather](https://t.me/BotFather) on Telegram, run `/newbot`, follow the prompts, and copy the bot token it gives you. (Manual step — no repo file changes.)

- [ ] **Step 2: Get your numeric Telegram user ID**

Message [@userinfobot](https://t.me/userinfobot) on Telegram and copy the numeric ID it replies with. (Manual step.)

- [ ] **Step 3: Pair the Telegram channel**

```bash
docker compose exec openclaw node openclaw.mjs channels add --channel telegram --token "<bot-token>"
```

Replace `<bot-token>` with the value from Step 1. Expected: confirmation the channel was added; `.openclaw/data/openclaw.json` now exists (or has been updated) with a `channels.telegram` section.

- [ ] **Step 4: Restrict who can message the agent**

Edit `.openclaw/data/openclaw.json` on the host (it's bind-mounted, so host edits apply to the running container) and, inside the existing structure OpenClaw generated, set:

```json
{
  "channels": {
    "telegram": {
      "allowFrom": ["<your-numeric-telegram-id>"],
      "dmPolicy": "allowlist"
    }
  }
}
```

Merge these keys into whatever OpenClaw already wrote — don't overwrite the rest of the file. Replace `<your-numeric-telegram-id>` with the value from Step 2.

- [ ] **Step 5: Apply the config change**

```bash
docker compose restart openclaw
```

Expected: `docker compose ps` shows `openclaw` back to `running` after the restart.

- [ ] **Step 6: Manual end-to-end verification**

Open the bot in Telegram and send it a message asking it to run `flutter --version` in `/workspace`. Expected: the reply includes the same Flutter version output verified in Task 2/4.

Then send a message asking it to make a trivial change and `git commit` it on the current branch. Expected: the commit is rejected, and the agent reports back that committing to the protected branch is not allowed — proving the Task 1 hook is enforced end-to-end through Telegram, not just via direct `docker compose exec`.

No repo commit results from this task (all changes are runtime state under the gitignored `.openclaw/data/`).
