#!/usr/bin/env bash
# Build Flutter APK and send it to Telegram.
# Triggered automatically by the post-merge git hook on master.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
# arm64-v8a only — ~6-8MB vs ~40MB fat APK; covers all modern Android phones
APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
TELEGRAM_CHAT_ID="6881839256"
BOT_TOKEN=$(python3 -c "import json; cfg=json.load(open('/home/node/.openclaw/openclaw.json')); print(cfg['channels']['telegram']['botToken'])")

echo "=== Flutter APK Build & Deploy ==="
echo "Building release APK..."

cd "$APP_DIR"
flutter build apk --release --split-per-abi 2>&1

if [ ! -f "$APK_PATH" ]; then
  echo "ERROR: APK not found at $APK_PATH"
  exit 1
fi

APK_SIZE=$(du -sh "$APK_PATH" | cut -f1)
GIT_HASH=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
GIT_MSG=$(git -C "$REPO_ROOT" log -1 --pretty=format:"%s")

echo "Build successful (${APK_SIZE}). Sending APK to Telegram..."

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
  -F "chat_id=${TELEGRAM_CHAT_ID}" \
  -F "document=@${APK_PATH};filename=app-release-arm64.apk" \
  -F "caption=New build ready — ${GIT_HASH}: ${GIT_MSG} (${APK_SIZE})" \
  | python3 -c "import json,sys; r=json.load(sys.stdin); print('Sent OK' if r.get('ok') else f'Error: {r}')"

echo "Done."
