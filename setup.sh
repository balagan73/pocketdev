#!/bin/bash
# pocket-dev setup wizard — select stacks and extensions, writes pocketdev.yaml
set -euo pipefail

POCKETDEV_YAML="$(dirname "$0")/pocketdev.yaml"
STACKS_DIR="$(dirname "$0")/stacks"
EXTENSIONS_DIR="$(dirname "$0")/extensions"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "  ____             _        _     ____             "
echo " |  _ \ ___   ___| | _____| |_  |  _ \  _____   __"
echo " | |_) / _ \ / __| |/ / _ \ __| | | | |/ _ \ \ / /"
echo " |  __/ (_) | (__|   <  __/ |_  | |_| |  __/\ V / "
echo " |_|   \___/ \___|_|\_\___|\__| |____/ \___| \_/  "
echo -e "${RESET}"
echo "  pocket-dev setup wizard"
echo ""

# --- Helper: read manifest field ---
read_field() {
    local file="$1" field="$2"
    grep "^${field}:" "$file" 2>/dev/null | sed "s/^${field}: *//"
}

# --- Discover available stacks ---
declare -a STACK_IDS=()
declare -a STACK_DESCS=()

if [ -d "$STACKS_DIR" ]; then
    for manifest in "$STACKS_DIR"/*/manifest.yaml; do
        [ -f "$manifest" ] || continue
        id=$(basename "$(dirname "$manifest")")
        desc=$(read_field "$manifest" description)
        STACK_IDS+=("$id")
        STACK_DESCS+=("$desc")
    done
fi

# --- Discover available extensions ---
declare -a EXT_IDS=()
declare -a EXT_DESCS=()

if [ -d "$EXTENSIONS_DIR" ]; then
    for manifest in "$EXTENSIONS_DIR"/*/manifest.yaml; do
        [ -f "$manifest" ] || continue
        id=$(basename "$(dirname "$manifest")")
        desc=$(read_field "$manifest" description)
        EXT_IDS+=("$id")
        EXT_DESCS+=("$desc")
    done
fi

# --- Select stacks ---
selected_stacks=()

if [ ${#STACK_IDS[@]} -eq 0 ]; then
    echo "No stacks available."
else
    echo -e "${BOLD}Available stacks:${RESET}"
    for i in "${!STACK_IDS[@]}"; do
        echo "  $((i+1)). ${STACK_IDS[$i]} — ${STACK_DESCS[$i]}"
    done
    echo ""
    echo -e "Select stacks (space-separated numbers, e.g. ${CYAN}1 2${RESET}, or press Enter for none):"
    read -r stack_input

    for num in $stack_input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#STACK_IDS[@]}" ]; then
            selected_stacks+=("${STACK_IDS[$((num-1))]}")
        else
            echo "  Ignoring invalid selection: $num"
        fi
    done
fi

echo ""

# --- Select extensions ---
selected_extensions=()

if [ ${#EXT_IDS[@]} -eq 0 ]; then
    echo "No extensions available."
else
    echo -e "${BOLD}Available extensions:${RESET}"
    for i in "${!EXT_IDS[@]}"; do
        echo "  $((i+1)). ${EXT_IDS[$i]} — ${EXT_DESCS[$i]}"
    done
    echo ""
    echo -e "Select extensions (space-separated numbers, or press Enter for none):"
    read -r ext_input

    for num in $ext_input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#EXT_IDS[@]}" ]; then
            selected_extensions+=("${EXT_IDS[$((num-1))]}")
        else
            echo "  Ignoring invalid selection: $num"
        fi
    done
fi

echo ""

# --- Write pocketdev.yaml ---
{
    echo "# pocket-dev configuration"
    echo "# Edit this file and run ./rebuild.sh to apply changes,"
    echo "# or run ./setup.sh to reconfigure interactively."
    echo ""
    echo "stacks:"
    if [ ${#selected_stacks[@]} -eq 0 ]; then
        echo "  []"
    else
        for s in "${selected_stacks[@]}"; do
            echo "  - $s"
        done
    fi
    echo ""
    echo "extensions:"
    if [ ${#selected_extensions[@]} -eq 0 ]; then
        echo "  []"
    else
        for e in "${selected_extensions[@]}"; do
            echo "  - $e"
        done
    fi
} > "$POCKETDEV_YAML"

echo -e "${GREEN}pocketdev.yaml written.${RESET}"
echo ""
echo "  Stacks:     ${selected_stacks[*]:-none}"
echo "  Extensions: ${selected_extensions[*]:-none}"
echo ""

# --- Offer to rebuild ---
echo -e "Build and start the container now? ${CYAN}[Y/n]${RESET}"
read -r build_now
if [[ "$build_now" =~ ^[Nn] ]]; then
    echo "Skipping build. Run ./rebuild.sh when ready."
else
    bash "$(dirname "$0")/rebuild.sh"
fi
