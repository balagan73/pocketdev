#!/bin/bash
# pocket-dev orchestrator — runs at Docker BUILD time
# Reads /pocket-dev/pocketdev.yaml and runs each stack's install.sh
set -euo pipefail

POCKETDEV_YAML="/pocket-dev/pocketdev.yaml"

echo "=== pocket-dev: build phase ==="

# Parse stacks list from pocketdev.yaml (lines under "stacks:" until next top-level key)
stacks=$(awk '/^stacks:/{found=1; next} found && /^[^ ]/{found=0} found && /^  - /{gsub(/^  - /, ""); print}' "$POCKETDEV_YAML")

if [ -z "$stacks" ]; then
    echo "No stacks selected — base image only."
else
    for stack in $stacks; do
        install_script="/pocket-dev/stacks/$stack/install.sh"
        if [ -f "$install_script" ]; then
            echo "--- Installing stack: $stack ---"
            chmod +x "$install_script"
            bash "$install_script"
            echo "--- Stack '$stack' installed ---"
        else
            echo "Warning: No install.sh found for stack '$stack' — skipping."
        fi
    done
fi

echo "=== pocket-dev: build phase complete ==="
