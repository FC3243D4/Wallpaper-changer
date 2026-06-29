#!/usr/bin/env bash
# colorChooser.sh
# Finds the best accent color from the current wallpaper using matugen.
# Outputs the chosen hex color (without #) to stdout.
# Usage: color=$(colorChooser.sh)

WALLPAPER="$HOME/.config/WallpaperChanger/.current_wallpaper"
BRIGHTNESS_THRESHOLD=20
color=""

for i in 0 1 2 3 4; do
    candidate=$(matugen image "$WALLPAPER" --source-color-index $i --dry-run 2>/dev/null \
        | grep -oP '#\K[0-9a-fA-F]{6}' | head -1)

    if [ -z "$candidate" ]; then
        matugen image "$WALLPAPER" --source-color-index $i --quiet 2>/dev/null
        candidate=$(cat ~/.cache/matugen/source-color 2>/dev/null | tr -d '[:space:]')
    fi

    [ -z "$candidate" ] && continue

    R=$((16#${candidate:0:2}))
    G=$((16#${candidate:2:2}))
    B=$((16#${candidate:4:2}))
    brightness=$(( (R * 299 + G * 587 + B * 114) / 1000 ))
    echo "Candidate $i: #$candidate (brightness: $brightness)" >&2

    if [ "$brightness" -ge "$BRIGHTNESS_THRESHOLD" ]; then
        color="$candidate"
        echo "Using candidate $i: #$color" >&2
        break
    fi
done

if [ -z "$color" ]; then
    echo "All matugen candidates too dark, falling back to dominantcolor..." >&2
    colorLine="$($HOME/.config/WallpaperChanger/themeRefresherSupportScripts/dominantcolor -m 1 -n 2 -e black -p dominant "$WALLPAPER" | grep -E '#')"
    color=$(echo "$colorLine" | tr -d '#')
fi

if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color'" >&2
    exit 1
fi

echo "${color,,}"
