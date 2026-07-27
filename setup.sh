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

# Always restore the cursor if we hid it during an interactive selection,
# even if the user Ctrl-C's out mid-selection.
trap 'tput cnorm 2>/dev/null || true' EXIT

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

# --- Helper: interactive checkbox multi-select (pure bash, ANSI escapes) ---
# Arrow keys (or j/k) move the cursor, space toggles the item, enter confirms.
# Usage: checkbox_select ids_array_name descs_array_name selected_array_name
checkbox_select() {
    local -n _ids="$1"
    local -n _descs="$2"
    local -n _selected="$3"
    local n="${#_ids[@]}"
    local -a checked=()
    local i cursor=0 key rest mark prefix

    for ((i = 0; i < n; i++)); do checked[i]=0; done

    echo -e "  (arrows or j/k to move, ${CYAN}space${RESET} to toggle, ${CYAN}enter${RESET} to confirm)"
    tput civis 2>/dev/null || true

    local drawn=0
    while true; do
        if [ "$drawn" -eq 1 ]; then
            printf '\033[%dA' "$n"
        fi
        drawn=1

        for ((i = 0; i < n; i++)); do
            printf '\033[2K\r'
            mark=" "
            prefix="  "
            [ "${checked[i]}" -eq 1 ] && mark="x"
            [ "$i" -eq "$cursor" ] && prefix="${CYAN}>${RESET} "
            if [ "${checked[i]}" -eq 1 ]; then
                echo -e "${prefix}[${GREEN}${mark}${RESET}] ${GREEN}${_ids[i]}${RESET} — ${_descs[i]}"
            else
                echo -e "${prefix}[${mark}] ${_ids[i]} — ${_descs[i]}"
            fi
        done

        rest=""
        if ! IFS= read -rsn1 key; then
            break
        fi
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.05 rest || true
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A'|k|K) cursor=$(( (cursor - 1 + n) % n )) ;;
            $'\x1b[B'|j|J) cursor=$(( (cursor + 1) % n )) ;;
            ' ') if [ "${checked[cursor]}" -eq 1 ]; then checked[cursor]=0; else checked[cursor]=1; fi ;;
            '') break ;;
        esac
    done
    tput cnorm 2>/dev/null || true

    _selected=()
    for ((i = 0; i < n; i++)); do
        if [ "${checked[i]}" -eq 1 ]; then
            _selected+=("${_ids[i]}")
        fi
    done
}

# --- Helper: numbered-list select (fallback when stdin is not a TTY) ---
# Usage: numbered_select ids_array_name descs_array_name selected_array_name "prompt text"
numbered_select() {
    local -n _ids="$1"
    local -n _descs="$2"
    local -n _selected="$3"
    local prompt="$4"
    local i num input

    for i in "${!_ids[@]}"; do
        echo "  $((i + 1)). ${_ids[$i]} — ${_descs[$i]}"
    done
    echo ""
    echo -e "$prompt"
    read -r input

    _selected=()
    for num in $input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#_ids[@]}" ]; then
            _selected+=("${_ids[$((num - 1))]}")
        else
            echo "  Ignoring invalid selection: $num"
        fi
    done
}

# --- Select stacks ---
selected_stacks=()

if [ ${#STACK_IDS[@]} -eq 0 ]; then
    echo "No stacks available."
else
    echo -e "${BOLD}Available stacks:${RESET}"
    if [ -t 0 ]; then
        checkbox_select STACK_IDS STACK_DESCS selected_stacks
    else
        numbered_select STACK_IDS STACK_DESCS selected_stacks \
            "Select stacks (space-separated numbers, e.g. ${CYAN}1 2${RESET}, or press Enter for none):"
    fi
fi

echo ""

# --- Select extensions ---
selected_extensions=()

if [ ${#EXT_IDS[@]} -eq 0 ]; then
    echo "No extensions available."
else
    echo -e "${BOLD}Available extensions:${RESET}"
    if [ -t 0 ]; then
        checkbox_select EXT_IDS EXT_DESCS selected_extensions
    else
        numbered_select EXT_IDS EXT_DESCS selected_extensions \
            "Select extensions (space-separated numbers, or press Enter for none):"
    fi
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
