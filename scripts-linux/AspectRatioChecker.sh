#!/usr/bin/env bash

# $1 = width
# $2 = height

#get resolution width and height of display
width=$(cut -d 'x' -f1 <<< $1)
height=$(cut -d 'x' -f2 <<< $1)

actual_ratio=$(awk "BEGIN {print $width/$height}")

declare -A ratios

cache_file="$HOME/.cache/wallpaper_ratios.cache"
cache_dir=$(dirname "$cache_file")
mkdir -p "$cache_dir"

if [[ -f "$cache_file" ]]; then
    while IFS='=' read -r key value; do
        ratios[$key]=$value
    done < "$cache_file"
else
    for dir in "$HOME/Pictures/wallpapers/"*; do
        dir_name=${dir##*/}
        width=${dir_name%%-*}
        height=${dir_name#*-}
        height=${height%%-*}
        ratio=$(awk "BEGIN {print $width/$height}")
        ratios[$ratio]=$dir_name/
    done
    
    for key in "${!ratios[@]}"; do
        echo "$key=${ratios[$key]}" >> "$cache_file"
    done
fi

closest_key=$(
for key in "${!ratios[@]}"; do
    awk -v a="$actual_ratio" -v b="$key" 'BEGIN{
        d=a-b; if(d<0)d=-d;
        printf "%.12f %s\n", d, b
    }'
done | sort -n | head -1 | awk '{print $2}'
)

echo "$HOME/Pictures/wallpapers/${ratios[$closest_key]}"