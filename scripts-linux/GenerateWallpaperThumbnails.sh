#!/usr/bin/env bash
# GenerateWallpaperThumbnails.sh
# Pre-generates thumbnails for all wallpapers to speed up the rofi
# wallpaper menu. Run once manually; later runs only process new/changed
# wallpapers.

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
echo "Found $total wallpapers. Generating thumbnails with $jobs parallel jobs..."

if [ "$total" -eq 0 ]; then
    echo "No wallpapers found, nothing to do."
    exit 0
fi

# Determine target aspect ratio: prefer the folder name (e.g. "16-9", "32-9"),
# fall back to reading the actual dimensions of the first wallpaper.
folderName=$(basename "$wallDir")
if [[ "$folderName" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    ratioW=${BASH_REMATCH[1]}
    ratioH=${BASH_REMATCH[2]}
    echo "Using aspect ratio from folder name: ${ratioW}:${ratioH}"
else
    dims=$(magick identify -format "%w %h" "${walls[0]}" 2>/dev/null)
    read -r ratioW ratioH <<< "$dims"
    if [ -z "$ratioW" ] || [ -z "$ratioH" ]; then
        echo "Could not determine aspect ratio, defaulting to 16:9"
        ratioW=16
        ratioH=9
    else
        echo "Using aspect ratio from first image (${walls[0]##*/}): ${ratioW}:${ratioH}"
    fi
fi

thumbHeight=$(( thumbWidth * ratioH / ratioW ))
thumbSize="${thumbWidth}x${thumbHeight}"
echo "Thumbnail size: $thumbSize"

generate_thumb() {
    local src="$1"
    local dst="$cacheDir/${src##*/}.jpg"

    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
        echo "SKIP"
        return
    fi

    magick "$src" -thumbnail "$thumbSize^" -gravity center \
        -extent "$thumbSize" -quality 80 "$dst" 2>/dev/null \
        && echo "OK" || echo "FAIL"
}

export -f generate_thumb
export cacheDir thumbSize

# Precomputed once: slicing these is far cheaper than spawning `seq` on
# every redraw, and emitting the whole bar via one printf means the
# terminal gets a single atomic write instead of several partial ones
# (the latter is what was causing the visible flicker).
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
minIntervalUs=80000   # 80ms between redraws — smooth but not flickery

while IFS= read -r line; do
    count=$((count + 1))
    case "$line" in
        OK) generated=$((generated + 1)) ;;
        SKIP) skipped=$((skipped + 1)) ;;
        FAIL) failed=$((failed + 1)) ;;
    esac

    # Throttle by wall-clock time rather than by item count, so the bar
    # updates at a smooth, constant rate whether you have 10 files or
    # 10,000, instead of jumping in big infrequent chunks. EPOCHREALTIME
    # is "seconds<sep>microseconds", where <sep> is the locale's decimal
    # point (e.g. ',' under it_IT, not '.') — strip any non-digit rather
    # than assuming '.', then diff as a plain integer without date/bc.
    nowUs="${EPOCHREALTIME//[^0-9]/}"
    if (( nowUs - lastDrawUs >= minIntervalUs )) || [ "$count" -eq "$total" ]; then
        draw_progress "$count" "$total"
        lastDrawUs="$nowUs"
    fi
done < <(printf '%s\0' "${walls[@]}" | \
    xargs -0 -P "$jobs" -I{} bash -c 'generate_thumb "$@"' _ {})

echo

echo "Done: $generated generated, $skipped skipped, $failed failed"
echo "Thumbnails stored in: $cacheDir"