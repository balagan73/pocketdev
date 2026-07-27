#!/bin/bash
# Piper extension — voice message synthesis (TTS), runs at container start
set -euo pipefail

OPENCLAW_DIR="/home/node/.openclaw"
PIPER_VENV="$OPENCLAW_DIR/piper-venv"
PIPER_BIN="$PIPER_VENV/bin/piper"

# Install piper-tts into a persistent venv on first run.
if [ ! -x "$PIPER_BIN" ]; then
  echo "Installing piper-tts (first run — cached in openclaw data dir)..."
  python3 -m venv "$PIPER_VENV" \
    && "$PIPER_VENV/bin/pip" install --quiet piper-tts \
    && echo "piper-tts installed." \
    || echo "Warning: piper-tts install failed"
fi

# Download the default voice model on first run.
PIPER_VOICES="$OPENCLAW_DIR/piper-voices"
PIPER_MODEL="$PIPER_VOICES/en_US-lessac-medium.onnx"
if [ ! -f "$PIPER_MODEL" ]; then
  echo "Downloading piper voice model (en_US-lessac-medium)..."
  mkdir -p "$PIPER_VOICES"
  BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
  curl -sL "$BASE/en_US-lessac-medium.onnx" -o "$PIPER_MODEL" \
    && curl -sL "$BASE/en_US-lessac-medium.onnx.json" -o "$PIPER_MODEL.json" \
    && echo "Voice model downloaded." \
    || echo "Warning: voice model download failed"
fi

# Wire piper into openclaw's TTS pipeline (tts-local-cli provider).
# messages.tts is protected; edit openclaw.json directly.
if [ -x "$PIPER_BIN" ] && [ -f "$PIPER_MODEL" ]; then
  python3 - << PYEOF
import json, sys
path = "$OPENCLAW_DIR/openclaw.json"
try:
    with open(path) as f:
        cfg = json.load(f)
    tts = cfg.setdefault("messages", {}).setdefault("tts", {})
    tts["enabled"] = True
    tts["auto"] = "inbound"
    providers = tts.setdefault("providers", {})
    entry = providers.setdefault("tts-local-cli", {})
    entry["command"] = "$PIPER_BIN"
    entry["args"] = ["--model", "$PIPER_MODEL", "--output-file", "{{OutputPath}}"]
    entry["outputFormat"] = "wav"
    # Enable the tts-local-cli plugin
    cfg.setdefault("plugins", {}).setdefault("entries", {}).setdefault("tts-local-cli", {})["enabled"] = True
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
    print("Configured piper TTS.")
except Exception as e:
    print(f"Warning: failed to configure piper TTS: {e}", file=sys.stderr)
PYEOF
fi
