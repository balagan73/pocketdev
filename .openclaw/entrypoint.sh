#!/bin/bash
set -euo pipefail

# Source stack runtime env vars written by install scripts at build time
if [ -d /pocket-dev/env ]; then
    for envfile in /pocket-dev/env/*.env; do
        [ -f "$envfile" ] && source "$envfile"
    done
fi

# Run extension install scripts (extensions don't require a Docker rebuild)
POCKETDEV_YAML="/pocket-dev/pocketdev.yaml"
if [ -f "$POCKETDEV_YAML" ]; then
    extensions=$(awk '/^extensions:/{found=1; next} found && /^[^ ]/{found=0} found && /^  - /{gsub(/^  - /, ""); print}' "$POCKETDEV_YAML")
    for ext in $extensions; do
        install_script="/pocket-dev/extensions/$ext/install.sh"
        if [ -f "$install_script" ]; then
            echo "pocket-dev: installing extension: $ext"
            bash "$install_script"
        fi
    done
fi

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
# Note: not explicitly sourced here — OpenClaw itself loads .env from $OPENCLAW_CONFIG_DIR on startup (confirmed by Task 4's health check).
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

# Ensure workspace plugins requiring capability consent are enabled on every start.
node openclaw.mjs plugins enable voice-session-reset --accept-capabilities 2>/dev/null || true

# --bind lan is required for Docker's bridge networking; loopback-only won't be reachable.
exec node openclaw.mjs gateway --allow-unconfigured --bind lan
