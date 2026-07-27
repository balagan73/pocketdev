#!/bin/bash
# Android SDK stack — runs at Docker BUILD time as root
set -euo pipefail

ANDROID_SDK_ROOT=/home/node/android-sdk
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT JAVA_HOME

apt-get update
apt-get install -y --no-install-recommends unzip openjdk-17-jdk-headless curl
rm -rf /var/lib/apt/lists/*

mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
    -o /tmp/cmdline-tools.zip
unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-tmp
mv /tmp/cmdline-tools-tmp/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-tmp

yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null 2>&1 || true
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
    "platform-tools" \
    "build-tools;36.0.0" \
    "platforms;android-36"
