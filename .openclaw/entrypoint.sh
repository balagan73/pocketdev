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

# Install faster-whisper into a persistent venv on first run (voice message transcription).
FW_VENV="/home/node/.openclaw/faster-whisper-venv"
if ! "$FW_VENV/bin/python3" -c "import faster_whisper" 2>/dev/null; then
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

# Write the faster-whisper transcription wrapper that openclaw shells out to.
cat > "$OPENCLAW_DIR/whisper-transcribe.py" << 'PYEOF'
#!/usr/bin/env python3
"""Transcribe audio file using faster-whisper, printing plain text to stdout."""
import sys, os
from faster_whisper import WhisperModel

if len(sys.argv) < 2:
    sys.exit("Usage: whisper-transcribe.py <audio-file>")

MODEL_DIR = os.path.expanduser("~/.openclaw/whisper-models")
os.makedirs(MODEL_DIR, exist_ok=True)
HALLUCINATIONS = {"you", "thank you.", "thank you", "thanks.", "thanks", "bye.", "bye"}

model = WhisperModel("small", device="cpu", compute_type="int8", download_root=MODEL_DIR)
segments, _ = model.transcribe(
    sys.argv[1],
    vad_filter=True,
    vad_parameters={"min_speech_duration_ms": 250},
)
for segment in segments:
    text = segment.text.strip()
    if text.lower() not in HALLUCINATIONS:
        print(text)
PYEOF

# Wire the wrapper into openclaw's local audio-transcription pipeline.
# Idempotent (same values every run) and runs before the gateway starts, so
# there's no live-reload race — just a plain file write.
node openclaw.mjs config patch --stdin << JSONEOF >/dev/null 2>&1 \
  && echo "Configured faster-whisper for voice transcription." \
  || echo "Warning: failed to configure audio transcription"
{
  tools: {
    media: {
      audio: {
        enabled: true,
        models: [
          {
            type: "cli",
            command: "$FW_VENV/bin/python3",
            args: ["$OPENCLAW_DIR/whisper-transcribe.py", "{{MediaPath}}"],
            timeoutSeconds: 120
          }
        ]
      }
    }
  }
}
JSONEOF

# If arguments were passed (docker compose exec/run <cmd>), run them directly.
# Otherwise start the gateway (docker compose up).
if [ $# -gt 0 ]; then
  exec "$@"
fi

# --bind lan is required for Docker's bridge networking; loopback-only won't be reachable.
exec node openclaw.mjs gateway --allow-unconfigured --bind lan
