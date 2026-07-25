#!/usr/bin/env bash
# Build Flutter APK and send it to Telegram.
# Triggered automatically by the post-merge git hook on master.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
TELEGRAM_CHAT_ID="6881839256"

echo "=== Flutter APK Build & Deploy ==="
echo "Building release APK..."

cd "$APP_DIR"
flutter build apk --release 2>&1

if [ ! -f "$APK_PATH" ]; then
  echo "ERROR: APK not found at $APK_PATH"
  exit 1
fi

APK_SIZE=$(du -sh "$APK_PATH" | cut -f1)
GIT_HASH=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
GIT_MSG=$(git -C "$REPO_ROOT" log -1 --pretty=format:"%s")

echo "Build successful (${APK_SIZE}). Sending to Telegram..."

openclaw message send \
  --channel telegram \
  --target "$TELEGRAM_CHAT_ID" \
  --media "$APK_PATH" \
  --force-document \
  --message "New build ready — ${GIT_HASH}: ${GIT_MSG} (${APK_SIZE})"

echo "Done. APK sent to Telegram."
