#!/usr/bin/env bash

# Default values
TARGET_WIDTH=3840
TARGET_HEIGHT=2160
JOBS=$(nproc)
BATCH=50

usage() {
  echo "Usage: $0 [directory] [width] [height]"
  echo "Defaults: directory=., width=3840, height=2160"
  exit 1
}

# Args
DIR="$(realpath "${1:-.}")"
TARGET_WIDTH="${2:-$TARGET_WIDTH}"
TARGET_HEIGHT="${3:-$TARGET_HEIGHT}"

# Check dependencies
command -v identify >/dev/null 2>&1 || {
  echo "Error: 'identify' (ImageMagick) not found."
  exit 1
}

echo "Scanning: $DIR"
echo "Expected: ${TARGET_WIDTH}x${TARGET_HEIGHT}, fully opaque"
echo

# Main pipeline
find "$DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -print0 \
| xargs -0 -n "$BATCH" -P "$JOBS" bash -c '
  for f do
    identify -format "$f, %w, %h, %[opaque]\n" "$f" 2>/dev/null
  done
' bash \
| awk -F ',' -v w="$TARGET_WIDTH" -v h="$TARGET_HEIGHT" -v base="$DIR/" '
{
  # Trim spaces
  gsub(/^ +| +$/, "", $2)
  gsub(/^ +| +$/, "", $3)
  gsub(/^ +| +$/, "", $4)

  # Remove absolute base path
  sub("^" base, "", $1)

  # Conditions
  bad_res = ($2 != w || $3 != h)
  bad_trans = ($4 != "True")

  if (bad_res || bad_trans) {
    label = (bad_res && bad_trans) ? "BOTH" :
            (bad_res ? "RESOLUTION" : "TRANSPARENCY")

    print $1 ", " $2 ", " $3 ", " $4 ", " label
  }
}
'
