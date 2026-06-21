#!/usr/bin/env bash
# Script written by @lesongvi for HG Logistics navigation voice mod
# Website: https://truckers.vn
# This script will download the latest version of ts-fmod-plugin.dll and copy it to the ETS2 and ATS game directories.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../configs/conf.ini"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file missing at $CONFIG_FILE" >&2
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file missing at $CONFIG_FILE" >&2
    exit 1
fi

HOST=$(awk -F '=' '/host/ {gsub(/[Domain" ]/, "", $2); print $2}' "$CONFIG_FILE")
VERSION=$(awk -F '=' '/version/ {gsub(/[ ]/, "", $2); print $2}' "$CONFIG_FILE")
ETS2_ROOT=$(awk -F '=' '/ets2_root/ {gsub(/[ ]/, "", $2); print $2}' "$CONFIG_FILE")
ATS_ROOT=$(awk -F '=' '/ats_root/ {gsub(/[ ]/, "", $2); print $2}' "$CONFIG_FILE")
VOLUME=$(printf "%.2f" "$(awk -F '=' '/volume/ {gsub(/[ ]/, "", $2); print $2 / 100}' "$CONFIG_FILE")")

FMOD_PLUGIN_URL="$HOST/plugins/ts-fmod-plugin/$VERSION/ts-fmod-plugin.dll"

install_mod() {
    local game_name="$1"
    local game_root="$2"
    local game_code="$3"
    
    local target_dir="$game_root/bin/win_x64/plugins"
    
    echo "----------------------------------------"
    echo "Installing HG Logistics navigation voice mod for $game_name..."
    
    mkdir -p "$target_dir"
    
    curl -sSL -o "$target_dir/ts-fmod-plugin.dll" "$FMOD_PLUGIN_URL"
    curl -sSL -o "$target_dir/ts-fmod-plugin/master.dll" "$HOST/plugins/ts-fmod-plugin/$VERSION/$game_code/master.dll"
    curl -sSL -o "$target_dir/ts-fmod-plugin/hg_navigation.bank" "$HOST/plugins/ts-fmod-plugin/$VERSION/hg_navigation.bank"
    curl -sSL -o "$target_dir/ts-fmod-plugin/hg_navigation.bank.guids" "$HOST/plugins/ts-fmod-plugin/$VERSION/hg_navigation.bank.guids"

    SELECTED_BANK_CONTENT=$(curl -sSL "$HOST/plugins/ts-fmod-plugin/$VERSION/selected.bank.txt")
    if [ -f "$target_dir/ts-fmod-plugin/selected.bank.txt" ]; then
        if [ -n "$SELECTED_BANK_CONTENT" ]; then
            while IFS= read -r line; do
                if [ -n "$line" ] && ! grep -Fxq "$line" "$target_dir/ts-fmod-plugin/selected.bank.txt"; then
                    echo "$line" >> "$target_dir/ts-fmod-plugin/selected.bank.txt"
                fi
            done <<< "$SELECTED_BANK_CONTENT"
        fi
    else
        echo "$SELECTED_BANK_CONTENT" > "$target_dir/ts-fmod-plugin/selected.bank.txt"
    fi
    
    if [ -f "$target_dir/ts-fmod-plugin/sound_levels.txt" ]; then
        sed -i 's/"navigation": [0-9.]\+/"navigation": '"$VOLUME"'/' "$target_dir/ts-fmod-plugin/sound_levels.txt"
    else
        SOUND_LEVELS_CONTENT=$(curl -sSL "$HOST/plugins/ts-fmod-plugin/$VERSION/sound_levels.txt")
        echo "$SOUND_LEVELS_CONTENT" | sed 's/"navigation": [0-9.]\+/"navigation": '"$VOLUME"'/' > "$target_dir/ts-fmod-plugin/sound_levels.txt"
    fi
    
    echo "$game_name installation complete."
}

if [ -d "$ETS2_ROOT" ]; then
    install_mod "Euro Truck Simulator 2" "$ETS2_ROOT" "ETS2"
else
    echo "ETS2 directory not found, skipping."
fi

if [ -d "$ATS_ROOT" ]; then
    install_mod "American Truck Simulator" "$ATS_ROOT" "ATS"
else
    echo "ATS directory not found, skipping."
fi