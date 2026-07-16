#!/usr/bin/env bash
# generateWallpaperThumbnails.sh
# Pre-generates thumbnails for all wallpapers to speed up rofi wallpaper menu.
# Run once manually; subsequent runs only process new/changed wallpapers.

wallBaseDIR="$HOME/Pictures/wallpapers"
if [ -d "$wallBaseDIR/16-9" ]; then
    wallDIR="$wallBaseDIR/16-9"
else
    wallDIR=$(find "$wallBaseDIR" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)
    if [ -z "$wallDIR" ]; then
        echo "No '16-9' folder found and no subfolders exist under $wallBaseDIR, exiting..."
        exit 1
    fi
    echo "'16-9' folder not found, falling back to: $wallDIR"
fi
CACHE_DIR="$HOME/.cache/wallpaper-thumbnails"
THUMB_WIDTH=300
JOBS=$(nproc)

mkdir -p "$CACHE_DIR"

mapfile -d '' walls < <(find -L "$wallDIR" -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)

total=${#walls[@]}
echo "Found $total wallpapers. Generating thumbnails with $JOBS parallel jobs..."

if [ "$total" -eq 0 ]; then
    echo "No wallpapers found, nothing to do."
    exit 0
fi

# Determine target aspect ratio: prefer the folder name (e.g. "16-9", "32-9"),
# fall back to reading the actual dimensions of the first wallpaper.
folderName=$(basename "$wallDIR")
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

THUMB_HEIGHT=$(( THUMB_WIDTH * ratioH / ratioW ))
THUMB_SIZE="${THUMB_WIDTH}x${THUMB_HEIGHT}"
echo "Thumbnail size: $THUMB_SIZE"

generate_thumb() {
    local src="$1"
    local dst="$CACHE_DIR/${src##*/}.jpg"

    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
        echo "SKIP"
        return
    fi

    magick "$src" -thumbnail "$THUMB_SIZE^" -gravity center \
        -extent "$THUMB_SIZE" -quality 80 "$dst" 2>/dev/null \
        && echo "OK" || echo "FAIL"
}

export -f generate_thumb
export CACHE_DIR THUMB_SIZE

# Precomputed once: slicing these is far cheaper than spawning `seq` on
# every redraw, and emitting the whole bar via one printf means the
# terminal gets a single atomic write instead of several partial ones
# (the latter is what was causing the visible flicker).
BAR_WIDTH=40
BAR_HASHES=$(printf '%*s' "$BAR_WIDTH" '' | tr ' ' '#')
BAR_SPACES=$(printf '%*s' "$BAR_WIDTH" '')

draw_progress() {
    local current="$1" total="$2"
    local filled=$(( current * BAR_WIDTH / total ))
    local percent=$(( current * 100 / total ))

    printf "\r[%s%s] %3d%% (%d/%d)\033[K" \
        "${BAR_HASHES:0:filled}" "${BAR_SPACES:0:BAR_WIDTH-filled}" \
        "$percent" "$current" "$total"
}

count=0
generated=0
skipped=0
failed=0
last_draw_us=0
min_interval_us=80000   # 80ms between redraws — smooth but not flickery

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
    now_us="${EPOCHREALTIME//[^0-9]/}"
    if (( now_us - last_draw_us >= min_interval_us )) || [ "$count" -eq "$total" ]; then
        draw_progress "$count" "$total"
        last_draw_us="$now_us"
    fi
done < <(printf '%s\0' "${walls[@]}" | \
    xargs -0 -P "$JOBS" -I{} bash -c 'generate_thumb "$@"' _ {})

echo

echo "Done: $generated generated, $skipped skipped, $failed failed"
echo "Thumbnails stored in: $CACHE_DIR"