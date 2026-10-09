#!/usr/bin/env bash
# GenerateWallpaperThumbnails.sh
# Pre-generates thumbnails and color caches for all wallpapers preserving folder structure.

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
thumbWidth=300
jobs=$(nproc)

mkdir -p "$cacheDir"

mapfile -d '' walls < <(find -L "$wallDir" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

total=${#walls[@]}
echo "Found $total wallpapers. Generating thumbnails and color cache with $jobs parallel jobs..."

if [ "$total" -eq 0 ]; then
    echo "No wallpapers found, nothing to do."
    exit 0
fi

folderName=$(basename "$wallDir")
if [[ "$folderName" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    ratioW=${BASH_REMATCH[1]}
    ratioH=${BASH_REMATCH[2]}
else
    dims=$(magick identify -format "%w %h" "${walls[0]}" 2>/dev/null)
    read -r ratioW ratioH <<< "$dims"
    if [ -z "$ratioW" ] || [ -z "$ratioH" ]; then
        ratioW=16
        ratioH=9
    fi
fi

thumbHeight=$(( thumbWidth * ratioH / ratioW ))
thumbSize="${thumbWidth}x${thumbHeight}"

generate_thumb() {
    local src="$1"
    
    # Compute relative path from wallDir to maintain folder structure in cache
    local relPath="${src#$wallDir/}"
    local targetDir="$cacheDir/$(dirname "$relPath")"
    mkdir -p "$targetDir"

    local dst="$targetDir/$(basename "$src").jpg"
    local colorDst="$targetDir/$(basename "$src").color"
    local brightnessThreshold=20

    # Skip if thumbnail and color cache both exist and are newer than source
    if [ -f "$dst" ] && [ -f "$colorDst" ] && [ "$dst" -nt "$src" ]; then
        echo "SKIP"
        return
    fi

    # 1. Generate thumbnail
    magick "$src" -thumbnail "$thumbSize^" -gravity center \
        -extent "$thumbSize" -quality 80 "$dst" 2>/dev/null || { echo "FAIL"; return; }

    # 2. Extract color
    local color=""
    local colorLine
    colorLine=$("$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/dominantcolor" -m 1 -n 2 -e black -p dominant "$src" 2>/dev/null | grep -E '#')
    local candidate=$(echo "$colorLine" | tr -d '#')

    if [ -n "$candidate" ]; then
        local r=$((16#${candidate:0:2}))
        local g=$((16#${candidate:2:2}))
        local b=$((16#${candidate:4:2}))
        local brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
        if [ "$brightness" -ge "$brightnessThreshold" ]; then
            color="$candidate"
        fi
    fi

    if [ -z "$color" ]; then
        for i in 0 1 2 3 4; do
            candidate=$(matugen image "$src" --source-color-index $i --dry-run 2>/dev/null \
                | grep -oP '#\K[0-9a-fA-F]{6}' | head -1)

            if [ -z "$candidate" ]; then
                matugen image "$src" --source-color-index $i --quiet >/dev/null 2>&1
                candidate=$(cat ~/.cache/matugen/source-color 2>/dev/null | tr -d '[:space:]')
            fi

            [ -z "$candidate" ] && continue

            local r=$((16#${candidate:0:2}))
            local g=$((16#${candidate:2:2}))
            local b=$((16#${candidate:4:2}))
            local brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))

            if [ "$brightness" -ge "$brightnessThreshold" ]; then
                color="$candidate"
                break
            fi
        done
    fi

    color=$(echo "$color" | grep -oP '[0-9a-fA-F]{6}' | tail -1)

    if [ ${#color} -eq 6 ]; then
        echo "${color,,}" > "$colorDst"
        echo "OK"
    else
        echo "FAIL"
    fi
}

export -f generate_thumb
export cacheDir thumbSize wallDir

barWidth=40
barHashes=$(printf '%*s' "$barWidth" '' | tr ' ' '#')
barSpaces=$(printf '%*s' "$barWidth" '')

draw_progress() {
    local current="$1" total="$2"
    local filled=$(( current * barWidth / total ))
    local percent=$(( current * 100 / total ))

    printf "\r[%s%s] %3d%% (%d/%d)\033[K" \
        "${barHashes:0:filled}" "${barSpaces:0:barWidth-filled}" \
        "$percent" "$current" "$total"
}

count=0
generated=0
skipped=0
failed=0
lastDrawUs=0
minIntervalUs=80000

while IFS= read -r line; do
    count=$((count + 1))
    case "$line" in
        OK) generated=$((generated + 1)) ;;
        SKIP) skipped=$((skipped + 1)) ;;
        FAIL) failed=$((failed + 1)) ;;
    esac

    nowUs="${EPOCHREALTIME//[^0-9]/}"
    if (( nowUs - lastDrawUs >= minIntervalUs )) || [ "$count" -eq "$total" ]; then
        draw_progress "$count" "$total"
        lastDrawUs="$nowUs"
    fi
done < <(printf '%s\0' "${walls[@]}" | \
    xargs -0 -P "$jobs" -I{} bash -c 'generate_thumb "$@"' _ {})

echo
echo "Done: $generated generated, $skipped skipped, $failed failed"
echo "Thumbnails & color cache stored in: $cacheDir"