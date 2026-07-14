#!/usr/bin/env bash
# colorChooser.sh
# Finds the best accent color from the current wallpaper using matugen.
# Outputs the chosen hex color (without #) to stdout.
# Usage: color=$(colorChooser.sh)

WALLPAPER="$HOME/.config/WallpaperChanger/.current_wallpaper"
BRIGHTNESS_THRESHOLD=20
color=""

colorLine="$($HOME/.config/WallpaperChanger/themeRefresherSupportScripts/dominantcolor -m 1 -n 2 -e black -p dominant "$WALLPAPER" | grep -E '#')"
candidate=$(echo "$colorLine" | tr -d '#')

R=$((16#${candidate:0:2}))
G=$((16#${candidate:2:2}))
B=$((16#${candidate:4:2}))
brightness=$(( (R * 299 + G * 587 + B * 114) / 1000 ))
echo "Candidate $i: #$candidate (brightness: $brightness)" >&2

if [ "$brightness" -ge "$BRIGHTNESS_THRESHOLD" ]; then
    color="$candidate"
    echo "Using candidate $i: #$color" >&2
fi

if [ -z "$color" ]; then
    echo "dominantcolor candidate too dark, falling back to matugen" >&2

    for i in 0 1 2 3 4; do
        candidate=$(matugen image "$WALLPAPER" --source-color-index $i --dry-run 2>/dev/null \
            | grep -oP '#\K[0-9a-fA-F]{6}' | head -1)

        if [ -z "$candidate" ]; then
            matugen image "$WALLPAPER" --source-color-index $i --quiet >/dev/null 2>&1
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
fi

# Defensive: strip anything that isn't a 6-char hex token, in case stray
# stdout (e.g. a matugen hook) got mixed into $color upstream.
color=$(echo "$color" | grep -oP '[0-9a-fA-F]{6}' | tail -1)

if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color'" >&2
    exit 1
fi

echo "${color,,}"