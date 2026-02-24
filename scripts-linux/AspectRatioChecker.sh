#!/usr/bin/env bash

# $1 = width
# $2 = height

actual_ratio=$(awk "BEGIN {print $1/$2}")
echo "Actual aspect ratio: $actual_ratio"

declare -A ratios=(
    [1.777777]="16-9"
    [2.333333]="21-9"
    [3.555555]="32-9"
    #[1.333333]="4-3"
    [1.6]="16-10"
    #[2.1]="21-10"
    #[3.2]="32-10"
    #[1.5]="3-2"
    #[0.5625]="9-16"
    #[0.428571]="9-21"
    #[0.28125]="9-32"
    #[0.75]="3-4"
    #[0.625]="10-16"
    #[0.47619]="10-21"
    #[0.3125]="10-32"
    #[0.666666]="2-3"
)

closest_key=$(
for key in "${!ratios[@]}"; do
    awk -v a="$actual_ratio" -v b="$key" 'BEGIN{
        d=a-b; if(d<0)d=-d;
        printf "%.12f %s\n", d, b
    }'
done | sort -n | head -1 | awk '{print $2}'
)

echo "$HOME/Pictures/wallpapers/${ratios[$closest_key]}"