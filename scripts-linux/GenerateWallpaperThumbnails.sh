#!/usr/bin/env bash
# GenerateWallpaperThumbnails.sh
# Pre-generates thumbnails and color caches for all wallpapers preserving folder structure.
# Up-to-date files are filtered out in the main shell (no forks), so only
# wallpapers that really need work are handed to the parallel workers.

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

# Half the cores: each job decodes full-size PNGs, so memory/CPU add up fast.
jobs=$(( $(nproc) / 2 ))
(( jobs < 1 )) && jobs=1

mkdir -p "$cacheDir"

mapfile -d '' walls < <(find -L "$wallDir" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

if [ "${#walls[@]}" -eq 0 ]; then
    echo "No wallpapers found, nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# Pre-filter: decide what to skip using only bash builtins (no process spawns).
# A wallpaper is up to date if its thumbnail and .color file both exist and
# the thumbnail is newer than the source.
# ---------------------------------------------------------------------------
todo=()
skipped=0
for src in "${walls[@]}"; do
    rel="${src#$wallDir/}"
    dst="$cacheDir/$rel.jpg"
    colorDst="$cacheDir/$rel.color"
    if [[ -f $dst && -f $colorDst && $dst -nt $src ]]; then
        skipped=$((skipped + 1))
    else
        todo+=("$src")
    fi
done

total=${#todo[@]}
echo "Found ${#walls[@]} wallpapers: $skipped up to date, $total to process (parallel jobs: $jobs)."

if [ "$total" -eq 0 ]; then
    echo "Nothing to do."
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

generate_thumb() {
    local src="$1"

    # Compute relative path from wallDir to maintain folder structure in cache
    # (pure parameter expansion, no dirname/basename forks)
    local relPath="${src#$wallDir/}"
    local relDir="${relPath%/*}"
    [ "$relDir" = "$relPath" ] && relDir="."
    local name="${src##*/}"
    local targetDir="$cacheDir/$relDir"

    local dst="$targetDir/$name.jpg"
    local colorDst="$targetDir/$name.color"
    local brightnessThreshold=20

    # Safety net: skip if thumbnail and color cache both exist and are newer than source
    if [ -f "$dst" ] && [ -f "$colorDst" ] && [ "$dst" -nt "$src" ]; then
        echo "SKIP"
        return
    fi

    mkdir -p "$targetDir"

    # 1. Generate thumbnail
    magick "$src" -thumbnail "$thumbSize^" -gravity center \
        -extent "$thumbSize" -quality 80 "$dst" 2>/dev/null || { echo "FAIL:thumbnail:$src"; return; }

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

    # Walk the quantized colors by frequency: handles images whose dominant
    # color is too dark but that still contain a usable lighter color.
    [ -z "$color" ] && color=$(pick_quantized "$src" "$brightnessThreshold")

    if [ -z "$color" ]; then
        for i in 0 1 2 3; do
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

    # Last resort: brightest quantized color, so the image is not retried forever
    [ -z "$color" ] && color=$(pick_quantized "$src" "$brightnessThreshold" any)

    color=$(echo "$color" | grep -oP '[0-9a-fA-F]{6}' | tail -1)

    if [ ${#color} -eq 6 ]; then
        echo "${color,,}" > "$colorDst"
        echo "OK"
    else
        echo "FAIL:color:$src"
    fi
}

export -f generate_thumb pick_quantized
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
failed=0
failedFiles=()
lastDrawUs=0
minIntervalUs=80000

while IFS= read -r line; do
    count=$((count + 1))
    case "$line" in
        OK) generated=$((generated + 1)) ;;
        SKIP) skipped=$((skipped + 1)) ;;
        FAIL:*)
            failed=$((failed + 1))
            failedFiles+=("${line#FAIL:}")
            ;;
    esac

    if [ -t 1 ]; then
        nowUs="${EPOCHREALTIME//[^0-9]/}"
        if (( nowUs - lastDrawUs >= minIntervalUs )) || [ "$count" -eq "$total" ]; then
            draw_progress "$count" "$total"
            lastDrawUs="$nowUs"
        fi
    elif (( count % 500 == 0 )) || [ "$count" -eq "$total" ]; then
        # Not a terminal (e.g. systemd/journal): plain readable lines, no \r bar
        echo "Progress: $count/$total"
    fi
done < <(printf '%s\0' "${todo[@]}" | \
    xargs -0 -P "$jobs" -I{} bash -c 'generate_thumb "$@"' _ {})

[ -t 1 ] && echo
echo "Done: $generated generated, $skipped skipped, $failed failed"
if [ "$failed" -gt 0 ]; then
    failLog="$cacheDir/failed.log"
    printf '%s\n' "${failedFiles[@]}" > "$failLog"
    echo "Failed files (step:path), also saved to $failLog:"
    printf '  %s\n' "${failedFiles[@]}"
fi
echo "Thumbnails & color cache stored in: $cacheDir"