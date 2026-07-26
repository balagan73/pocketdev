#!/bin/bash
# Telegram extension — tunes Telegram streaming behavior, runs at container start
set -euo pipefail

CONFIG_FILE="$(dirname "$0")/config.yaml"

read_field() {
    local field="$1" default="$2" value=""
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep "^${field}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${field}: *//" | tr -d '"')
    fi
    echo "${value:-$default}"
}

STREAMING_MODE=$(read_field "streaming_mode" "progress")
TOOL_PROGRESS=$(read_field "tool_progress" "false")

# See config.yaml for what these settings do and why "progress" avoids the
# flash-and-disappear effect on partial answers and tool output.
node openclaw.mjs config patch --stdin << JSONEOF >/dev/null 2>&1 \
  && echo "Configured Telegram streaming mode ($STREAMING_MODE)." \
  || echo "Warning: failed to configure Telegram streaming mode"
{ channels: { telegram: { streaming: { mode: "$STREAMING_MODE", progress: { toolProgress: $TOOL_PROGRESS } } } } }
JSONEOF
