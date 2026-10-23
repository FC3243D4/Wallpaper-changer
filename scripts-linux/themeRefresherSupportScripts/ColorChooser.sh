#!/usr/bin/env bash
# ColorChooser.sh
# Checks structured cache for wallpaper accent color. Falls back to dynamic calculation if missing.

wallBaseDir="$HOME/Pictures/wallpapers"
if [ -d "$wallBaseDir/16-9" ]; then
    wallDir="$wallBaseDir/16-9"
else
    wallDir=$(find "$wallBaseDir" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)
fi

wallpaperPath="$HOME/.config/WallpaperChanger/.current_wallpaper"
resolvedWallpaper=$(realpath "$wallpaperPath" 2>/dev/null || echo "$wallpaperPath")

cacheDir="$HOME/.cache/wallpaper-thumbnails"
relPath="${resolvedWallpaper#$wallDir/}"
targetCacheDir="$cacheDir/$(dirname "$relPath")"
wallpaperName=$(basename "$resolvedWallpaper")
colorCacheFile="$targetCacheDir/${wallpaperName}.color"
brightnessThreshold=20
color=""

# 1. Check structured cache first
if [ -f "$colorCacheFile" ]; then
    cachedColor=$(cat "$colorCacheFile" | tr -d '[:space:]')
    if [[ "$cachedColor" =~ ^[0-9a-fA-F]{6}$ ]]; then
        echo "Cache hit for $wallpaperName: #$cachedColor" >&2
        echo "${cachedColor,,}"
        exit 0
    fi
fi

echo "Cache miss for $wallpaperName, generating color..." >&2

# 2. Dynamic generation fallback
colorLine="$($HOME/.config/WallpaperChanger/themeRefresherSupportScripts/dominantcolor -m 1 -n 2 -e black -p dominant "$wallpaperPath" | grep -E '#')"
candidate=$(echo "$colorLine" | tr -d '#')

if [ -n "$candidate" ]; then
    r=$((16#${candidate:0:2}))
    g=$((16#${candidate:2:2}))
    b=$((16#${candidate:4:2}))
    brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
    if [ "$brightness" -ge "$brightnessThreshold" ]; then
        color="$candidate"
    fi
fi

if [ -z "$color" ]; then
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

        if [ "$brightness" -ge "$brightnessThreshold" ]; then
            color="$candidate"
            break
        fi
    done
fi

color=$(echo "$color" | grep -oP '[0-9a-fA-F]{6}' | tail -1)

if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color'" >&2
    exit 1
fi

# 3. Save to structured cache for next time
mkdir -p "$targetCacheDir"
echo "${color,,}" > "$colorCacheFile"

echo "${color,,}"