#!/usr/bin/env bash
# ColorChooser.sh
# Checks structured cache for wallpaper accent color. Falls back to dynamic calculation if missing.
# The fallback logic must stay identical to GenerateWallpaperThumbnails.sh so a
# cache hit and a cache miss always give the same color.

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

# Prints the most frequent quantized color that passes the brightness threshold.
# With mode "any", falls back to the brightest color found when none passes,
# so very dark images still get a valid color instead of failing forever.
pick_quantized() {
    local img="$1" threshold="${2:-20}" mode="${3:-strict}"
    local cnt hex r g b br bestBr=-1 bestHex=""
    while read -r cnt hex; do
        [ -z "$hex" ] && continue
        r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
        br=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
        if (( br >= threshold )); then echo "$hex"; return 0; fi
        if (( br > bestBr )); then bestBr=$br; bestHex="$hex"; fi
    done < <(magick "$img" -alpha off +repage -scale 50x50! -depth 8 +dither \
                 -colors 2 -depth 8 -format '%c' histogram:info: 2>/dev/null \
             | sed -n 's/^ *\([0-9]\+\):.*#\([0-9a-fA-F]\{6\}\) .*/\1 \2/p' | sort -rn)
    if [ "$mode" = any ] && [ -n "$bestHex" ]; then echo "$bestHex"; return 0; fi
    return 1
}

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
# Dominant color: downscale to 50x50, quantize to 2 colors, pick the most frequent
candidate=$(magick "$wallpaperPath" -alpha off +repage -scale 50x50! -depth 8 +dither -colors 2 -depth 8 -format '%c' histogram:info: | sed -n 's/^ *\([0-9]\+\):.*#\([0-9a-fA-F]\{6\}\) .*/\1 \2/p' | sort -rn | head -n 1 | cut -d' ' -f2)

if [ -n "$candidate" ]; then
    r=$((16#${candidate:0:2}))
    g=$((16#${candidate:2:2}))
    b=$((16#${candidate:4:2}))
    brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
    if [ "$brightness" -ge "$brightnessThreshold" ]; then
        color="$candidate"
    fi
fi

# Walk the quantized colors by frequency: handles images whose dominant
# color is too dark but that still contain a usable lighter color.
[ -z "$color" ] && color=$(pick_quantized "$wallpaperPath" "$brightnessThreshold")

if [ -z "$color" ]; then
    for i in 0 1 2 3; do
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

# Last resort: brightest quantized color, so very dark images do not fail
[ -z "$color" ] && color=$(pick_quantized "$wallpaperPath" "$brightnessThreshold" any)

color=$(echo "$color" | grep -oP '[0-9a-fA-F]{6}' | tail -1)

if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color'" >&2
    exit 1
fi

# 3. Save to structured cache for next time
mkdir -p "$targetCacheDir"
echo "${color,,}" > "$colorCacheFile"

echo "${color,,}"