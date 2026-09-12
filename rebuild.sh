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

# If usage-metrics is selected, auto-include the metrics overlay via
# COMPOSE_FILE (read by `docker compose` from a root .env with no -f flags
# needed). Only the COMPOSE_FILE line itself is added/removed/updated --
# .env may also hold a user-set GRAFANA_ADMIN_PASSWORD (see
# .openclaw/README.md), which must survive every rebuild untouched.
selected_extensions=$(awk '/^extensions:/{found=1; next} found && /^[^ ]/{found=0} found && /^  - /{gsub(/^  - /, ""); print}' "$POCKETDEV_YAML")
if echo "$selected_extensions" | grep -qx "usage-metrics"; then
    touch .env
    if grep -q '^COMPOSE_FILE=' .env; then
        sed -i 's|^COMPOSE_FILE=.*|COMPOSE_FILE=docker-compose.yml:docker-compose.metrics.yml|' .env
    else
        echo "COMPOSE_FILE=docker-compose.yml:docker-compose.metrics.yml" >> .env
    fi
    echo "usage-metrics selected: Prometheus/Grafana will be brought up automatically."
else
    if [ -f .env ]; then
        sed -i '/^COMPOSE_FILE=/d' .env
        [ -s .env ] || rm -f .env
    fi
    echo "usage-metrics not selected: metrics overlay excluded."
fi

echo "=== pocket-dev: rebuilding container ==="
docker compose up -d --build --remove-orphans
echo "=== pocket-dev: rebuild complete ==="
