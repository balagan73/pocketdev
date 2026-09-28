#!/usr/bin/env bash
# Switch the Discord voice channel live between the container's own OpenClaw
# agent (stt-tts, any model from OpenClaw's model catalog) and a realtime
# provider (e.g. OpenAI GPT-Realtime) — a config patch against the running
# Gateway, no image rebuild.
#
# Usage:
#   scripts/discord-voice-mode.sh list                          # models in OpenClaw's catalog (* = active)
#   scripts/discord-voice-mode.sh model <provider/model> [--dry-run]  # stt-tts, answered by that model
#   scripts/discord-voice-mode.sh default  [--dry-run]          # stt-tts with config.yaml's voice_model
#   scripts/discord-voice-mode.sh realtime [--dry-run]          # bidi: realtime provider converses, consults the agent
#   scripts/discord-voice-mode.sh status                        # print the active voice config
#
# `model` accepts only a key printed by `list` (the output of
# `openclaw models list --all --plain`); anything else is rejected. `claude`
# is accepted as an alias for `default`.
#
# Runs from the host (via `docker exec`, container name from $POCKETDEV_CONTAINER,
# default "pocketdev") or from inside the container (calls `openclaw` directly).
#
# Realtime provider/model/voice come from extensions/discord-voice/config.yaml
# (realtime_provider / realtime_model / realtime_voice), the same values
# install.sh applies at container start. If
# extensions/discord-voice/realtime-instructions.txt exists, its contents are
# set as realtime.instructions.
#
# Note: install.sh re-applies the default voice mode and model on every
# container start (stt-tts + voice_model, unless DISCORD_VOICE_MODE /
# DISCORD_VOICE_MODEL or config.yaml say otherwise), so a switch made here
# lasts until the next container restart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$SCRIPT_DIR/../extensions/discord-voice"
CONFIG_FILE="$EXT_DIR/config.yaml"
INSTRUCTIONS_FILE="$EXT_DIR/realtime-instructions.txt"
CONTAINER="${POCKETDEV_CONTAINER:-pocketdev}"

usage() {
    sed -n '7,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

TARGET="${1:-}"
[ $# -gt 0 ] && shift
MODEL_ARG=""
if [ "$TARGET" = "model" ]; then
    MODEL_ARG="${1:-}"
    [ -n "$MODEL_ARG" ] || usage
    shift
fi
DRY_RUN=""
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN="--dry-run" ;;
    *) usage ;;
esac

# Run a command in the OpenClaw container, stdin passed through.
oc() {
    if command -v openclaw >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
        "$@"
    else
        docker exec -i "$CONTAINER" "$@"
    fi
}

# Same reader as extensions/discord-voice/install.sh.
read_field() {
    local field="$1" default="$2" value=""
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^${field}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${field}: *//" | tr -d '"')
    fi
    echo "${value:-$default}"
}

# OpenClaw's own model catalog, one provider/model key per line.
catalog() {
    oc openclaw models list --all --plain
}

active_model() {
    oc openclaw config get channels.discord.voice.model 2>/dev/null | tr -d '"' || true
}

show_status() {
    oc node -e '
        let s = "";
        process.stdin.on("data", d => s += d).on("end", () => {
            const v = JSON.parse(s);
            const rt = v.realtime;
            const who = v.mode === "stt-tts" ? "OpenClaw agent, no realtime provider"
                      : "realtime (" + (rt ? rt.provider + "/" + rt.model + ", voice " + rt.speakerVoice : "no realtime block!") + ")";
            console.log("Discord voice mode: " + v.mode + " -> " + who);
            if (v.mode !== "stt-tts" && rt) console.log("  instructions: " + (rt.instructions ? rt.instructions.length + " chars" : "not set"));
            console.log("  agent model: " + (v.model || "(inherits routed agent model)"));
        });
    ' < <(oc openclaw config get channels.discord.voice)
}

# stt-tts is the only voice mode with no realtime provider in the loop
# (agent-proxy still uses one as its audio front end). realtime: null deletes
# the block so nothing references the provider while in this mode.
stt_tts_patch() {
    echo "{ channels: { discord: { voice: { enabled: true, mode: \"stt-tts\", model: \"$1\", realtime: null } } } }"
}

case "$TARGET" in
    list)
        ACTIVE=$(active_model)
        catalog | while IFS= read -r key; do
            [ -n "$key" ] || continue
            if [ "$key" = "$ACTIVE" ]; then echo "* $key"; else echo "  $key"; fi
        done
        exit 0
        ;;
    model)
        # `config patch` accepts any string for voice.model, so check the key
        # against the live catalog here rather than finding out mid-call.
        CATALOG=$(catalog) || { echo "Error: could not read OpenClaw's model catalog." >&2; exit 1; }
        if ! grep -Fxq -- "$MODEL_ARG" <<< "$CATALOG"; then
            echo "Error: '$MODEL_ARG' is not in OpenClaw's model catalog. Available models:" >&2
            sed 's/^/  /' <<< "$CATALOG" >&2
            exit 1
        fi
        PATCH=$(stt_tts_patch "$MODEL_ARG")
        ;;
    default|claude)
        PATCH=$(stt_tts_patch "$(read_field voice_model anthropic/claude-haiku-4-5)")
        ;;
    realtime)
        PROVIDER=$(read_field realtime_provider openai)
        MODEL=$(read_field realtime_model gpt-realtime-2.1)
        VOICE=$(read_field realtime_voice cedar)
        INSTRUCTIONS_JSON=""
        if [ -f "$INSTRUCTIONS_FILE" ]; then
            # node for JSON string-escaping (commas, quotes, newlines) — same
            # approach as the discord-voice extension; jq isn't in the image.
            INSTRUCTIONS_JSON=", instructions: $(oc node -e '
                let s = ""; process.stdin.on("data", d => s += d)
                    .on("end", () => console.log(JSON.stringify(s.trim())));
            ' < "$INSTRUCTIONS_FILE")"
        fi
        PATCH="{ channels: { discord: { voice: { enabled: true, mode: \"bidi\", realtime: { provider: \"$PROVIDER\", model: \"$MODEL\", speakerVoice: \"$VOICE\"$INSTRUCTIONS_JSON } } } } }"
        ;;
    status)
        show_status
        exit 0
        ;;
    *)
        usage
        ;;
esac

echo "$PATCH" | oc openclaw config patch --stdin $DRY_RUN
if [ -n "$DRY_RUN" ]; then
    echo "Dry run only — nothing changed."
    exit 0
fi

# No restart needed, despite what `config patch` may print: the Gateway
# watches openclaw.json and hot-reloads by restarting just the Discord channel
# (the bot drops out of voice for ~2s and auto-rejoins in the new mode). A
# no-op patch triggers no reload. Give it a moment, then report what is live.
sleep 3
show_status
