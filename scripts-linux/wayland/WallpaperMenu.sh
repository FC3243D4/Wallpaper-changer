#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */
# This script for selecting wallpapers

get_monitor_info() {
    if command -v hyprctl &>/dev/null; then
        focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
        scale_factor=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .scale')
        monitor_height=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .height')
    elif command -v swaymsg &>/dev/null; then
        focused_monitor=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
        scale_factor=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .scale')
        monitor_height=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .current_mode.height')
    elif command -v wlr-randr &>/dev/null; then
        focused_monitor=$(wlr-randr --json | jq -r '.[0].name')
        scale_factor=$(wlr-randr --json | jq -r '.[0].scale')
        monitor_height=$(wlr-randr --json | jq -r '.[0].modes[] | select(.current) | .height')
    else
        # Fallback: sane defaults, icon size will clamp to 20 anyway
        focused_monitor="unknown"
        scale_factor=1
        monitor_height=1080
    fi
}

# WALLPAPERS PATH
wallDIR="$HOME/Pictures/wallpapers/16-9"
CACHE_DIR="$HOME/.cache/wallpaper-thumbnails"

# Directory for swaync
iDIR="$HOME/.config/swaync/images"

# Variables
rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi"
get_monitor_info()

# Ensure focused_monitor is detected
if [[ -z "$focused_monitor" ]]; then
    notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Could not detect focused monitor"
    exit 1
fi

icon_size=$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc)
adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
rofi_override="element-icon{size:${adjusted_icon_size}%;}"

# Retrieve wallpapers
mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
RANDOM_PIC_NAME=". random"

# Rofi command
rofi_command="rofi -i -show -dmenu -config $rofi_theme -theme-str $rofi_override"

# Pre-load all existing thumbnail names into associative array (one readdir vs 11k stat calls)
declare -A THUMB_EXISTS
while IFS= read -r f; do
    THUMB_EXISTS["$f"]=1
done < <(find "$CACHE_DIR" -maxdepth 1 -name "*.jpg" -printf "%f\n" 2>/dev/null)

# Build sorted menu using pure bash string ops (no subshells in the loop)
menu() {
    IFS=$'\n' sorted_options=($(sort <<<"${PICS[*]}"))

    # Random entry
    local rkey="${RANDOM_PIC##*/}.jpg"
    if [ -n "${THUMB_EXISTS[$rkey]+x}" ]; then
        printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$CACHE_DIR/$rkey"
    else
        printf "%s\x00icon\x1f%s\n" "$RANDOM_PIC_NAME" "$RANDOM_PIC"
    fi

    for pic in "${sorted_options[@]}"; do
        local key="${pic##*/}.jpg"
        if [ -n "${THUMB_EXISTS[$key]+x}" ]; then
            printf "%s\x00icon\x1f%s\n" "${pic##*/}" "$CACHE_DIR/$key"
        else
            # Generate thumbnail async for next time
            magick "$pic" -thumbnail "300x169^" -gravity center \
                -extent "300x169" -quality 80 "$CACHE_DIR/$key" 2>/dev/null &
            disown
            printf "%s\x00icon\x1f%s\n" "${pic##*/}" "$pic"
        fi
    done
}

# Main function
main() {
    choice=$(menu | $rofi_command)
    choice=$(echo "$choice" | xargs)
    RANDOM_PIC_NAME=$(echo "$RANDOM_PIC_NAME" | xargs)

    if [[ -z "$choice" ]]; then
        echo "No choice selected. Exiting."
        exit 0
    fi

    # Handle random selection
    if [[ "$choice" == "$RANDOM_PIC_NAME" ]]; then
        choice="${RANDOM_PIC##*/}"
    fi

    choice_basename="${choice%.*}"

    # Search for the selected file
    selected_file=$(find "$wallDIR" -iname "$choice_basename.*" -print -quit)

    if [[ -z "$selected_file" ]]; then
        echo "File not found. Selected choice: $choice"
        exit 1
    fi

    # Get relative path
    selected_file=${selected_file#*$HOME/Pictures/wallpapers/}
    selected_file=$(echo "$selected_file" | sed 's,^[^/]*/,,')
    selected_file="/$selected_file"
    echo "Selected file path: $selected_file"

    $HOME/.config/WallpaperChanger/WallpaperApplicator.sh $selected_file
}

# Check if rofi is already running
if pidof rofi >/dev/null; then
    pkill rofi
fi

main