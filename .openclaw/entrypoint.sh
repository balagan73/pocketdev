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

# Install faster-whisper into a persistent venv on first run (voice message transcription).
FW_VENV="/home/node/.openclaw/faster-whisper-venv"
FW_BIN="$FW_VENV/bin/pip"
if [ ! -x "$FW_BIN" ]; then
  echo "Installing faster-whisper (first run — cached in openclaw data dir)..."
  rm -rf "$FW_VENV"
  python3 -m venv "$FW_VENV" \
    && "$FW_VENV/bin/pip" install --quiet faster-whisper \
    && echo "faster-whisper installed." \
    || echo "Warning: faster-whisper install failed"
fi
if [ -x "$FW_VENV/bin/python3" ]; then
  export PATH="$FW_VENV/bin:$PATH"
fi

# If arguments were passed (docker compose exec/run <cmd>), run them directly.
# Otherwise start the gateway (docker compose up).
if [ $# -gt 0 ]; then
  exec "$@"
fi

# --bind lan is required for Docker's bridge networking; loopback-only won't be reachable.
exec node openclaw.mjs gateway --allow-unconfigured --bind lan
