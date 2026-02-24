#!/usr/bin/env bash

# $1 = width
# $2 = height

# Calculate actual aspect ratio
actual_ratio=$(awk "BEGIN {printf \"%.2f\", $1/$2}")

# Define known ratios
declare -A ratios=(
    [1.77]="16-9"
    #[2.33]="21-9"
    [3.55]="32-9"
    #[1.33]="4-3"
    [1.60]="16-10"
    #[2.10]="21-10"
    #[3.20]="32-10"
    #[1.50]="3-2"
    #[0.56]="9-16"
    #[0.42]="9-21"
    #[0.28]="9-32"
    #[0.75]="3-4"
    #[0.62]="10-16"
    #[0.48]="10-21"
    #[0.31]="10-32"
    #[0.66]="2-3"
)

# Find closest ratio
closest_key=$(for key in "${!ratios[@]}"; do
    echo "$key"
done | awk -v target="$actual_ratio" '{print ($0-target)^2, $0}' | sort -n | head -1 | awk '{print $2}')

echo "$HOME/Pictures/wallpapers/${ratios[$closest_key]}"
exit 0