#!/bin/bash
# Linux desktop stack — runs at Docker BUILD time as root
set -euo pipefail

FLUTTER_HOME=/home/node/flutter

# Package list per Flutter's official Linux desktop setup docs (verified
# 2026-07-26 against docs.flutter.dev/platform-integration/linux/setup):
# clang/cmake/ninja-build/pkg-config/libgtk-3-dev are what `flutter doctor`
# itself checks for; liblzma-dev and libstdc++-12-dev are additional build
# dependencies the docs call out (libstdc++-12-dev in particular fixes a
# link error on Debian/Ubuntu releases defaulting to gcc-12, which this
# base image does).
apt-get update
apt-get install -y --no-install-recommends \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev
rm -rf /var/lib/apt/lists/*

# Enabling the Linux desktop build target is a `flutter config` toggle, not
# an apt package — it requires Flutter to already be installed by the
# `flutter` stack. Per orchestrate.sh, stacks run in the order listed in
# pocketdev.yaml, so if `flutter` isn't listed first (or isn't selected at
# all), skip this step without failing the build — the apt packages above
# are still useful on their own, and the toggle can be applied later.
if [ -x "$FLUTTER_HOME/bin/flutter" ]; then
    # The flutter stack's own install.sh chowns $FLUTTER_HOME to node:node
    # as its last step, so by the time we (still root) get here, git sees
    # this repo as owned by a different user and refuses to operate on it
    # ("dubious ownership") — `flutter config` shells out to git internally.
    git config --global --add safe.directory "$FLUTTER_HOME"
    "$FLUTTER_HOME/bin/flutter" config --enable-linux-desktop
else
    echo "Warning: Flutter not found at $FLUTTER_HOME/bin/flutter — skipping" \
        "'flutter config --enable-linux-desktop'. List the 'flutter' stack" \
        "before 'linux-desktop' in pocketdev.yaml's stacks: list, or run" \
        "'flutter config --enable-linux-desktop' manually afterward."
fi
