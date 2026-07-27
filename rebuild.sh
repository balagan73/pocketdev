#!/bin/bash
# Rebuild and restart the pocket-dev container with current pocketdev.yaml selections.
set -euo pipefail

cd "$(dirname "$0")"

POCKETDEV_YAML="pocketdev.yaml"
ENV_OUT=".openclaw/pocketdev-stacks.env"
BASE_IMAGE=$(awk '/^FROM /{print $2; exit}' .openclaw/Dockerfile)

echo "=== pocket-dev: resolving stack env ==="
mkdir -p .openclaw
docker image inspect "$BASE_IMAGE" > /dev/null 2>&1 || docker pull "$BASE_IMAGE"
BASE_PATH=$(docker image inspect "$BASE_IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | awk -F= '$1=="PATH"{print substr($0, index($0,"=")+1)}')

selected_stacks=$(awk '/^stacks:/{found=1; next} found && /^[^ ]/{found=0} found && /^  - /{gsub(/^  - /, ""); print}' "$POCKETDEV_YAML")

var_names=""
for stack in $selected_stacks; do
    env_file="stacks/$stack/env.sh"
    [ -f "$env_file" ] || continue
    names=$(grep -oE '^export [A-Z_][A-Z0-9_]*=' "$env_file" | sed -E 's/^export ([A-Z_][A-Z0-9_]*)=/\1/')
    var_names="$var_names $names"
done
var_names=$(echo "$var_names" | tr ' ' '\n' | sort -u)

(
    PATH="$BASE_PATH"
    for stack in $selected_stacks; do
        env_file="stacks/$stack/env.sh"
        [ -f "$env_file" ] && source "$env_file"
    done
    for name in $var_names; do
        echo "$name=${!name}"
    done
) > "$ENV_OUT"

echo "=== pocket-dev: rebuilding container ==="
docker compose up -d --build
echo "=== pocket-dev: rebuild complete ==="
