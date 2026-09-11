#!/bin/bash
# Update the pinned OpenClaw version in .openclaw/Dockerfile and roll it
# out safely against the live container.
#
# Encodes the sequence worked out by hand during the 2026.6.33 -> 2026.9.4
# upgrade: verified backup, clean stop before any state migration, an
# isolated `doctor --fix`, and reconciliation of externally-installed
# (ClawHub/npm) plugins, which can go ABI-incompatible with a new core
# even when bundled plugins never do. See .openclaw/README.md's
# "Updating OpenClaw" section for what each step is protecting against.
set -euo pipefail

cd "$(dirname "$0")"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>  (e.g. $0 2026.9.4)" >&2
    echo "Browse available versions: https://github.com/openclaw/openclaw/pkgs/container/openclaw" >&2
    exit 1
fi

TARGET_VERSION="$1"
NEW_IMAGE="ghcr.io/openclaw/openclaw:${TARGET_VERSION}"
CURRENT_IMAGE="$(awk '/^FROM /{print $2; exit}' .openclaw/Dockerfile)"
BACKUP_DIR="${OPENCLAW_BACKUP_DIR:-$HOME/backups/pocketdev}"

# From here on, any failure (via set -e) should restore the original
# Dockerfile pin rather than leave it bumped with no rollback.
ROLLBACK_NEEDED=1
rollback_on_failure() {
    if [ "$ROLLBACK_NEEDED" = "1" ]; then
        echo
        echo "=== FAILED: rolling back .openclaw/Dockerfile to $CURRENT_IMAGE ===" >&2
        sed -i "0,/^FROM /s#^FROM .*#FROM ${CURRENT_IMAGE}#" .openclaw/Dockerfile
        echo "Rolled back. Your original pin is restored; the gateway container itself may still need manual attention — check 'docker compose ps' and the backup noted above." >&2
    fi
}
trap rollback_on_failure EXIT

echo "=== pocket-dev: update-openclaw ==="
echo "Current pin: $CURRENT_IMAGE"
echo "Target:      $NEW_IMAGE"
echo

if [ "$CURRENT_IMAGE" = "$NEW_IMAGE" ]; then
    echo "Already pinned to $NEW_IMAGE. Nothing to do."
    ROLLBACK_NEEDED=0
    exit 0
fi

echo "Verifying $NEW_IMAGE exists on the registry..."
docker manifest inspect "$NEW_IMAGE" > /dev/null

echo
echo "=== Step 1/8: back up real state (verified) ==="
mkdir -p "$BACKUP_DIR"
docker compose exec -T openclaw mkdir -p /tmp/openclaw-update-backup
BACKUP_JSON="$(docker compose exec -T openclaw node openclaw.mjs backup create --output /tmp/openclaw-update-backup --verify --json)"
echo "$BACKUP_JSON"
BACKUP_ARCHIVE="$(echo "$BACKUP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["archivePath"])')"
docker compose cp "openclaw:${BACKUP_ARCHIVE}" "$BACKUP_DIR/"
echo "Backup saved to $BACKUP_DIR/$(basename "$BACKUP_ARCHIVE")"

echo
echo "=== Step 2/8: pin the new version in the Dockerfile ==="
sed -i "0,/^FROM /s#^FROM .*#FROM ${NEW_IMAGE}#" .openclaw/Dockerfile
grep '^FROM ' .openclaw/Dockerfile

echo
echo "=== Step 3/8: rebuild with the pinned image ==="
docker compose build --pull

echo
echo "=== Step 4/8: stop the running gateway cleanly ==="
# Must happen before doctor --fix: running it against a live, still-serving
# container risks two processes touching the same SQLite state at once.
docker compose stop openclaw

echo
echo "=== Step 5/8: run doctor --fix in isolation ==="
# A one-off invocation (bypasses the normal entrypoint's gateway auto-start)
# so exactly one process touches the real state while it migrates.
docker compose run --rm --entrypoint bash openclaw -c "node openclaw.mjs doctor --non-interactive --fix"

echo
echo "=== Step 6/8: bring the gateway back up ==="
docker compose up -d
echo "Waiting for startup..."
sleep 20

echo
echo "=== Step 7/8: reconcile externally-installed plugins ==="
# Bundled plugins live under /app/dist/extensions and are versioned in
# lockstep with core. Externally-installed ones (trust.installSource
# "clawhub" or "npm") are compiled separately and can be ABI-incompatible
# with the new core even though their config/version looks fine.
PLUGIN_IDS="$(docker compose exec -T openclaw node openclaw.mjs plugins list --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    if p.get('trust', {}).get('installSource') in ('clawhub', 'npm'):
        print(p['id'])
")"

if [ -n "$PLUGIN_IDS" ]; then
    echo "Externally-installed plugins found: $PLUGIN_IDS"
    for pid in $PLUGIN_IDS; do
        echo "Updating plugin: $pid"
        docker compose exec -T openclaw node openclaw.mjs plugins update "$pid" \
          || echo "Warning: failed to update plugin $pid — check it manually (openclaw plugins inspect $pid --runtime --json)"
    done
    echo "Restarting to load updated plugins..."
    docker compose restart
    echo "Waiting for startup..."
    sleep 20
else
    echo "No externally-installed plugins found — nothing to reconcile."
fi

echo
echo "=== Step 8/8: verify ==="
docker compose exec -T openclaw node openclaw.mjs --version
docker compose exec -T openclaw node openclaw.mjs status --deep --timeout 15000

ROLLBACK_NEEDED=0

echo
echo "=== pocket-dev: update complete ==="
echo "Review the status output above — channel state (Discord/Telegram/etc.)"
echo "needs a human read, this script only confirms the gateway responds."
echo "Backup: $BACKUP_DIR/$(basename "$BACKUP_ARCHIVE")"
