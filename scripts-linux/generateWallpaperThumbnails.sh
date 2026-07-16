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

results=$(printf '%s\0' "${walls[@]}" | \
    xargs -0 -P "$JOBS" -I{} bash -c 'generate_thumb "$@"' _ {})

generated=$(echo "$results" | grep -c "^OK$")
skipped=$(echo "$results" | grep -c "^SKIP$")
failed=$(echo "$results" | grep -c "^FAIL$")

echo "Done: $generated generated, $skipped skipped, $failed failed"
echo "Thumbnails stored in: $CACHE_DIR"