#!/bin/bash
# Chrome stack — runs at Docker BUILD time as root
set -euo pipefail

apt-get update
# Debian's chromium package pulls in the standard headless-Chrome shared
# libraries (libnss3, libgbm1, libasound2, libatk-bridge2.0-0, etc.)
# automatically via its own apt dependency chain, even with
# --no-install-recommends. fonts-liberation and libxss1 are added explicitly
# since they aren't always guaranteed transitive deps but are commonly
# needed for headless rendering/screenshots.
apt-get install -y --no-install-recommends chromium fonts-liberation libxss1
rm -rf /var/lib/apt/lists/*
