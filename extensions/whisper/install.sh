#!/bin/bash
# Whisper extension — voice message transcription, runs at container start
set -euo pipefail

OPENCLAW_DIR="/home/node/.openclaw"
FW_VENV="$OPENCLAW_DIR/faster-whisper-venv"

# Install faster-whisper into a persistent venv on first run.
if ! "$FW_VENV/bin/python3" -c "import faster_whisper" 2>/dev/null; then
  echo "Installing faster-whisper (first run — cached in openclaw data dir)..."
  rm -rf "$FW_VENV"
  python3 -m venv "$FW_VENV" \
    && "$FW_VENV/bin/pip" install --quiet faster-whisper \
    && echo "faster-whisper installed." \
    || echo "Warning: faster-whisper install failed"
fi

# Write the faster-whisper transcription wrapper that openclaw shells out to.
mkdir -p "$OPENCLAW_DIR"
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
    language="en",
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
      audio: { enabled: true },
      models: [
        {
          type: "cli",
          capabilities: ["audio"],
          command: "$FW_VENV/bin/python3",
          args: ["$OPENCLAW_DIR/whisper-transcribe.py", "{{MediaPath}}"],
          timeoutSeconds: 120
        }
      ]
    }
  }
}
JSONEOF
