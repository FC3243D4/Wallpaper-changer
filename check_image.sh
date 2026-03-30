#!/usr/bin/env bash

trap 'echo "Stopping..."; kill -- -$$' SIGINT SIGTERM

# Default values
TARGET_WIDTH=3840
TARGET_HEIGHT=2160
JOBS=$(($(nproc) / 4))
BATCH=50

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [DIRECTORY] [WIDTH] [HEIGHT]

Scan images and report files that:
- Do not match the target resolution
- Contain transparency

OPTIONS:
  -h, --help        Show this help message and exit

  --16-9            Set resolution to 3840x2160
  --16-10           Set resolution to 3840x2400
  --21-9            Set resolution to 5120x2160
  --32-9            Set resolution to 7680x2160

ARGS:
  DIRECTORY         Target directory (default: current directory)
  WIDTH             Expected width (overridden by flags)
  HEIGHT            Expected height (overridden by flags)

EXAMPLES:
  $0
  $0 ./images
  $0 ./images 1920 1080
  $0 --21-9 ./images

OUTPUT:
  path, width, height, opaque, ISSUE
EOF
  exit 0
}

# Parse flags
while [[ "$1" == --* || "$1" == "-h" ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;

    --16-9)
      TARGET_WIDTH=3840
      TARGET_HEIGHT=2160
      shift
      ;;

    --16-10)
      TARGET_WIDTH=3840
      TARGET_HEIGHT=2400
      shift
      ;;

    --21-9)
      TARGET_WIDTH=5120
      TARGET_HEIGHT=2160
      shift
      ;;

    --32-9)
      TARGET_WIDTH=7680
      TARGET_HEIGHT=2160
      shift
      ;;

    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Positional args
DIR="$(realpath "${1:-.}")"

# Only use manual width/height if no preset flag was used
if [[ -n "$2" && -n "$3" ]]; then
  TARGET_WIDTH="$2"
  TARGET_HEIGHT="$3"
fi

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
