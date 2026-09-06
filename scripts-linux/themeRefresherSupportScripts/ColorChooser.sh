#!/usr/bin/env bash
# ColorChooser.sh
# Picks an accent color from the current wallpaper: tries dominantcolor
# first, falls back to matugen's candidate source colors if that one is
# too dark to read as an accent. Prints the winning hex (no '#') to stdout.
# Usage: color=$(ColorChooser.sh)

wallpaperPath="$HOME/.config/WallpaperChanger/.current_wallpaper"
brightnessThreshold=20
color=""

colorLine="$($HOME/.config/WallpaperChanger/themeRefresherSupportScripts/dominantcolor -m 1 -n 2 -e black -p dominant "$wallpaperPath" | grep -E '#')"
candidate=$(echo "$colorLine" | tr -d '#')

r=$((16#${candidate:0:2}))
g=$((16#${candidate:2:2}))
b=$((16#${candidate:4:2}))
brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
echo "Candidate: #$candidate (brightness: $brightness)" >&2

if [ "$brightness" -ge "$brightnessThreshold" ]; then
    color="$candidate"
    echo "Using dominantcolor candidate: #$color" >&2
fi

if [ -z "$color" ]; then
    echo "dominantcolor candidate too dark, falling back to matugen" >&2

    for i in 0 1 2 3 4; do
        candidate=$(matugen image "$wallpaperPath" --source-color-index $i --dry-run 2>/dev/null \
            | grep -oP '#\K[0-9a-fA-F]{6}' | head -1)

        if [ -z "$candidate" ]; then
            matugen image "$wallpaperPath" --source-color-index $i --quiet >/dev/null 2>&1
            candidate=$(cat ~/.cache/matugen/source-color 2>/dev/null | tr -d '[:space:]')
        fi

        [ -z "$candidate" ] && continue

        r=$((16#${candidate:0:2}))
        g=$((16#${candidate:2:2}))
        b=$((16#${candidate:4:2}))
        brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
        echo "Candidate $i: #$candidate (brightness: $brightness)" >&2

        if [ "$brightness" -ge "$brightnessThreshold" ]; then
            color="$candidate"
            echo "Using candidate $i: #$color" >&2
            break
        fi
    done
fi

# Defensive: keep only a trailing 6-hex-digit token, in case stray stdout
# from a matugen hook got mixed into $color above.
color=$(echo "$color" | grep -oP '[0-9a-fA-F]{6}' | tail -1)

if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color'" >&2
    exit 1
fi

echo "${color,,}"