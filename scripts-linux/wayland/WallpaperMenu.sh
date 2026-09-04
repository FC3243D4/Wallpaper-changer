#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */
# WallpaperMenu.sh (Wayland)
# Rofi menu for picking a wallpaper (or "random"), showing cached
# thumbnails where available and generating them on the fly otherwise.

get_monitor_info() {
    if command -v hyprctl &>/dev/null; then
        focusedMonitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
        scaleFactor=$(hyprctl monitors -j | jq -r --arg mon "$focusedMonitor" '.[] | select(.name == $mon) | .scale')
        monitorHeight=$(hyprctl monitors -j | jq -r --arg mon "$focusedMonitor" '.[] | select(.name == $mon) | .height')
    elif command -v swaymsg &>/dev/null; then
        focusedMonitor=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
        scaleFactor=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .scale')
        monitorHeight=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .current_mode.height')
    elif command -v wlr-randr &>/dev/null; then
        focusedMonitor=$(wlr-randr --json | jq -r '.[0].name')
        scaleFactor=$(wlr-randr --json | jq -r '.[0].scale')
        monitorHeight=$(wlr-randr --json | jq -r '.[0].modes[] | select(.current) | .height')
    else
        # Fallback: sane defaults, icon size will clamp to 20 anyway
        focusedMonitor="unknown"
        scaleFactor=1
        monitorHeight=1080
    fi
}

# Wallpapers path
wallBaseDir="$HOME/Pictures/wallpapers"
if [ -d "$wallBaseDir/16-9" ]; then
    wallDir="$wallBaseDir/16-9"
else
    wallDir=$(find "$wallBaseDir" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)
    if [ -z "$wallDir" ]; then
        echo "No '16-9' folder found and no subfolders exist under $wallBaseDir, exiting..."
        exit 1
    fi
    echo "'16-9' folder not found, falling back to: $wallDir"
fi
cacheDir="$HOME/.cache/wallpaper-thumbnails"

# Directory for swaync
iconDir="$HOME/.config/swaync/images"

# Variables
rofiTheme="$HOME/.config/rofi/config-wallpaper.rasi"
get_monitor_info

# Ensure focusedMonitor is detected
if [[ -z "$focusedMonitor" ]]; then
    notify-send -i "$iconDir/error.png" "E-R-R-O-R" "Could not detect focused monitor"
    exit 1
fi

iconSize=$(echo "scale=1; ($monitorHeight * 3) / ($scaleFactor * 150)" | bc)
adjustedIconSize=$(echo "$iconSize" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
rofiOverride="element-icon{size:${adjustedIconSize}%;}"

# Retrieve wallpapers
mapfile -d '' pics < <(find -L "${wallDir}" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

randomPic="${pics[$((RANDOM % ${#pics[@]}))]}"
randomPicName=". random"

# Rofi command
rofiCommand="rofi -i -show -dmenu -config $rofiTheme -theme-str $rofiOverride"

# Pre-load all existing thumbnail names into an associative array (one
# readdir vs 11k stat calls)
declare -A thumbExists
while IFS= read -r f; do
    thumbExists["$f"]=1
done < <(find "$cacheDir" -maxdepth 1 -name "*.jpg" -printf "%f\n" 2>/dev/null)

# Build sorted menu using pure bash string ops (no subshells in the loop)
menu() {
    IFS=$'\n' sortedOptions=($(sort <<<"${pics[*]}"))

    # Random entry
    local randomKey="${randomPic##*/}.jpg"
    if [ -n "${thumbExists[$randomKey]+x}" ]; then
        printf "%s\x00icon\x1f%s\n" "$randomPicName" "$cacheDir/$randomKey"
    else
        printf "%s\x00icon\x1f%s\n" "$randomPicName" "$randomPic"
    fi

    for pic in "${sortedOptions[@]}"; do
        local key="${pic##*/}.jpg"
        if [ -n "${thumbExists[$key]+x}" ]; then
            printf "%s\x00icon\x1f%s\n" "${pic##*/}" "$cacheDir/$key"
        else
            # Generate thumbnail async for next time
            magick "$pic" -thumbnail "300x169^" -gravity center \
                -extent "300x169" -quality 80 "$cacheDir/$key" 2>/dev/null &
            disown
            printf "%s\x00icon\x1f%s\n" "${pic##*/}" "$pic"
        fi
    done
}

main() {
    choice=$(menu | $rofiCommand)
    choice=$(echo "$choice" | xargs)
    randomPicName=$(echo "$randomPicName" | xargs)

    if [[ -z "$choice" ]]; then
        echo "No choice selected. Exiting."
        exit 0
    fi

    # Handle random selection
    if [[ "$choice" == "$randomPicName" ]]; then
        choice="${randomPic##*/}"
    fi

    choiceBasename="${choice%.*}"

    # Search for the selected file
    selectedFile=$(find "$wallDir" -iname "$choiceBasename.*" -print -quit)

    if [[ -z "$selectedFile" ]]; then
        echo "File not found. Selected choice: $choice"
        exit 1
    fi

    # Get relative path
    selectedFile=${selectedFile#*$HOME/Pictures/wallpapers/}
    selectedFile=$(echo "$selectedFile" | sed 's,^[^/]*/,,')
    selectedFile="/$selectedFile"
    echo "Selected file path: $selectedFile"

    $HOME/.config/WallpaperChanger/WallpaperApplicator.sh $selectedFile
}

# Check if rofi is already running
if pidof rofi >/dev/null; then
    pkill rofi
fi

main