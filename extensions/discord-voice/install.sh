#!/bin/bash
# Discord voice extension — wires up continuous Talk mode over a Discord
# voice channel (stt-tts mode: reuses the container's whisper transcription
# + piper TTS), runs at container start
set -euo pipefail

CONFIG_FILE="$(dirname "$0")/config.yaml"

read_field() {
    local field="$1" default="$2" value=""
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^${field}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${field}: *//" | tr -d '"')
    fi
    echo "${value:-$default}"
}

# Container env vars override config.yaml, so realtime can be opted into at
# container start without editing the baked-in config (e.g. add
# DISCORD_VOICE_MODE=bidi to the compose environment). Default: stt-tts.
VOICE_MODE="${DISCORD_VOICE_MODE:-$(read_field "voice_mode" "stt-tts")}"
case "$VOICE_MODE" in
    claude) VOICE_MODE="stt-tts" ;;   # same names scripts/discord-voice-mode.sh uses
    realtime) VOICE_MODE="bidi" ;;
esac
TTS_PROVIDER=$(read_field "tts_provider" "tts-local-cli")
REALTIME_PROVIDER="${REALTIME_PROVIDER:-$(read_field "realtime_provider" "openai")}"
REALTIME_MODEL="${REALTIME_MODEL:-$(read_field "realtime_model" "gpt-realtime-2.1")}"
REALTIME_VOICE="${REALTIME_VOICE:-$(read_field "realtime_voice" "cedar")}"

# The Discord channel ships as a separate plugin, not bundled with OpenClaw
# core (unlike Telegram) — install it if it isn't already present.
if ! node openclaw.mjs plugins list 2>/dev/null | grep -qi discord; then
    node openclaw.mjs plugins install @openclaw/discord >/dev/null 2>&1 \
      && echo "Installed Discord channel plugin." \
      || echo "Warning: failed to install Discord channel plugin"
fi

# Only non-secret, environment-agnostic settings are patched here. The bot
# token and guild/channel allowlist are secrets / environment-specific IDs
# that this script can't know — see .openclaw/README.md's "Discord voice"
# section for the one-time manual setup (same pattern as the Telegram
# botToken, which also lives only in .openclaw/data/openclaw.json, never
# in a committed file).
#
# realtime_provider/model/voice (agent-proxy/bidi only) are plain product
# choices, not secrets, so they're templated here same as mode/tts_provider
# — the API key itself is never in this script or config.yaml; it's read
# from OPENAI_API_KEY (see config.yaml's comment) at request time.
#
# In stt-tts the realtime block is deleted (realtime: null), matching
# `scripts/discord-voice-mode.sh claude`, so a realtime block left in the
# persisted openclaw.json by an earlier live switch doesn't linger.
if [ "$VOICE_MODE" = "stt-tts" ]; then
  REALTIME_JSON=", realtime: null"
else
  REALTIME_JSON=", realtime: { provider: \"$REALTIME_PROVIDER\", model: \"$REALTIME_MODEL\", speakerVoice: \"$REALTIME_VOICE\" }"
fi

node openclaw.mjs config patch --stdin << JSONEOF >/dev/null 2>&1 \
  && echo "Configured Discord voice mode ($VOICE_MODE, tts: $TTS_PROVIDER)." \
  || echo "Warning: failed to configure Discord voice mode"
{ channels: { discord: { voice: { enabled: true, mode: "$VOICE_MODE", tts: { provider: "$TTS_PROVIDER" }$REALTIME_JSON } } } }
JSONEOF

# --- Voice session reset (bundled with discord-voice — meaningless on its
# own, so not its own selectable extension) ---
#
# Installs the local voice-session-reset plugin (lets a user say a trigger
# phrase in the voice channel to reset the session in place, with
# confirmation — no container/Gateway restart needed for the reset itself)
# and enables the conversation-access hook it needs. Installed from the
# bind-mounted repo path (/workspace), not a baked image path, so this
# extension keeps the same "restart only, no rebuild" guarantee as every
# other extension.
if ! node openclaw.mjs plugins list 2>/dev/null | grep -qi voice-session-reset; then
    node openclaw.mjs plugins install --link /workspace/extensions/voice-session-reset/plugin >/dev/null 2>&1 \
      && echo "Installed voice-session-reset plugin." \
      || echo "Warning: failed to install voice-session-reset plugin"
fi

node openclaw.mjs config patch --stdin << JSONEOF >/dev/null 2>&1 \
  && echo "Configured voice-session-reset plugin (allowConversationAccess)." \
  || echo "Warning: failed to configure voice-session-reset plugin"
{ plugins: { entries: { "voice-session-reset": { hooks: { allowConversationAccess: true } } } } }
JSONEOF

# NOTE: the operator.admin scope grant that voice-session-reset needs is NOT
# done here. This script runs during the entrypoint's extension-install loop,
# which completes before the entrypoint execs the Gateway — so no Gateway is
# listening yet and a `gateway call` here cannot work. The plugin performs the
# bootstrap itself from its `gateway_start` hook instead.
