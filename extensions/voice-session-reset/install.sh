#!/bin/bash
# Voice session reset extension — installs the local voice-session-reset
# plugin and enables the conversation-access hook it needs. Runs at
# container start (see .openclaw/entrypoint.sh).
set -euo pipefail

if ! node openclaw.mjs plugins list 2>/dev/null | grep -qi voice-session-reset; then
    node openclaw.mjs plugins install --link /pocket-dev/extensions/voice-session-reset/plugin >/dev/null 2>&1 \
      && echo "Installed voice-session-reset plugin." \
      || echo "Warning: failed to install voice-session-reset plugin"
fi

node openclaw.mjs config patch --stdin << JSONEOF >/dev/null 2>&1 \
  && echo "Configured voice-session-reset plugin (allowConversationAccess)." \
  || echo "Warning: failed to configure voice-session-reset plugin"
{ plugins: { entries: { "voice-session-reset": { hooks: { allowConversationAccess: true } } } } }
JSONEOF
