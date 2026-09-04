#!/usr/bin/env bash
# AspectRatioChecker.sh
# Echoes the wallpaper folder (e.g. "16-9/") whose aspect ratio is closest
# to the given display resolution. Folder ratios are cached on first run
# so later calls don't have to recompute them.
# Usage: AspectRatioChecker.sh <WIDTHxHEIGHT>

width=$(cut -d 'x' -f1 <<< $1)
height=$(cut -d 'x' -f2 <<< $1)

actualRatio=$(awk "BEGIN {print $width/$height}")

declare -A ratios

cacheFile="$HOME/.cache/wallpaper_ratios.cache"
cacheDir=$(dirname "$cacheFile")
mkdir -p "$cacheDir"

if [[ -f "$cacheFile" ]]; then
    while IFS='=' read -r key value; do
        ratios[$key]=$value
    done < "$cacheFile"
else
    for dir in "$HOME/Pictures/wallpapers/"*; do
        dirName=${dir##*/}
        width=${dirName%%-*}
        height=${dirName#*-}
        height=${height%%-*}
        ratio=$(awk "BEGIN {print $width/$height}")
        ratios[$ratio]=$dirName/
    done

    for key in "${!ratios[@]}"; do
        echo "$key=${ratios[$key]}" >> "$cacheFile"
    done
fi

closestKey=$(
for key in "${!ratios[@]}"; do
    awk -v a="$actualRatio" -v b="$key" 'BEGIN{
        d=a-b; if(d<0)d=-d;
        printf "%.12f %s\n", d, b
    }'
done | sort -n | head -1 | awk '{print $2}'
)

echo "$HOME/Pictures/wallpapers/${ratios[$closestKey]}"