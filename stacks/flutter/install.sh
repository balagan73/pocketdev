#!/bin/bash
# Flutter stack — runs at Docker BUILD time as root
set -euo pipefail

FLUTTER_HOME=/home/node/flutter
export FLUTTER_HOME
export PATH="$FLUTTER_HOME/bin:$PATH"

apt-get update
apt-get install -y --no-install-recommends xz-utils curl
rm -rf /var/lib/apt/lists/*

# --depth 1 means flutter's own update-check has no tag/history to verify
# freshness against, so `flutter doctor` may nag "new version available"
# even when this is genuinely current stable (verified 2026-07-26: installed
# hash matched current_release.stable in Flutter's release feed). Cosmetic
# only — flutter --version is unaffected. Not fixed intentionally: the
# "upgrade" path here is rebuilding the image, which re-clones stable fresh.
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
"$FLUTTER_HOME/bin/flutter" config --enable-web --enable-android --no-analytics
"$FLUTTER_HOME/bin/flutter" precache --web --android

"$FLUTTER_HOME/bin/flutter" doctor -v || true

# Cloned/configured as root at build time but flutter runs as node at
# container runtime — git refuses to operate on a repo it doesn't own.
chown -R node:node "$FLUTTER_HOME"
