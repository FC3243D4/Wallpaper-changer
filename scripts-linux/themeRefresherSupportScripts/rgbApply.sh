#!/usr/bin/env bash
# rgbApply.sh
# Applies accent color to OpenRGB and Logitech G devices.
# Usage: rgbApply.sh <hex_color>
# Example: rgbApply.sh a986d3

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

if openrgb --version &>/dev/null; then
    echo "Applying color to OpenRGB..."
    openrgb -c "$color" >/dev/null 2>&1 &
    disown
fi

if ratbagctl --version &>/dev/null; then
    (
        devices=($(ratbagctl list | grep -oP '^[\w-]+(?=:)'))
        for device in "${devices[@]}"; do
            profiles=($(ratbagctl "$device" info | grep -oP '^Profile \K\d+'))
            for profile in "${profiles[@]}"; do
                ratbagctl "$device" profile $profile led 0 set mode on color "$color"
            done
        done
    ) &
    disown
fi
