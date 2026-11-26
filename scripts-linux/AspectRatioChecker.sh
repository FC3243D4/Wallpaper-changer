#!/usr/bin/env bash
# AspectRatioChecker.sh
# Echoes the wallpaper folder (e.g. "16-9/") whose aspect ratio is closest
# to the given display resolution. Folder ratios are cached on first run
# so later calls don't have to recompute them.
# Usage: AspectRatioChecker.sh <WIDTHxHEIGHT> [BASE_DIR]
# With BASE_DIR the ratio folders are read from that directory instead of the
# installed wallpapers (the installer uses this to ask "which of the repo's
# ratios does this display need?"): nothing is cached and the printed path is
# under BASE_DIR.

width=$(cut -d 'x' -f1 <<< $1)
height=$(cut -d 'x' -f2 <<< $1)

actualRatio=$(awk "BEGIN {print $width/$height}")

wallBase="${2:-$HOME/Pictures/wallpapers}"

declare -A ratios

cacheFile="$HOME/.cache/wallpaper_ratios.cache"
cacheDir=$(dirname "$cacheFile")
mkdir -p "$cacheDir"

if [[ -z "$2" && -f "$cacheFile" ]]; then
    while IFS='=' read -r key value; do
        ratios[$key]=$value
    done < "$cacheFile"
else
    for dir in "$wallBase/"*; do
        [[ -d "$dir" ]] || continue
        dirName=${dir##*/}
        width=${dirName%%-*}
        height=${dirName#*-}
        height=${height%%-*}
        ratio=$(awk "BEGIN {print $width/$height}")
        ratios[$ratio]=$dirName/
    done

    if [[ -z "$2" ]]; then
        for key in "${!ratios[@]}"; do
            echo "$key=${ratios[$key]}" >> "$cacheFile"
        done
    fi
fi

closestKey=$(
for key in "${!ratios[@]}"; do
    awk -v a="$actualRatio" -v b="$key" 'BEGIN{
        d=a-b; if(d<0)d=-d;
        printf "%.12f %s\n", d, b
    }'
done | sort -n | head -1 | awk '{print $2}'
)

echo "$wallBase/${ratios[$closestKey]}"