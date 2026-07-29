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

# --- Near-white / low-saturation correction ---
# Pastel colors (low saturation) read as washed-out/white on cheap LED
# strips no matter which channels are numerically high. Convert to HSV and,
# if saturation is below MIN_SATURATION, raise it to that floor while
# keeping hue and value (brightness) unchanged. This keeps the color
# recognizable (e.g. "faint orange") without letting it collapse to white.
min_saturation=0.80      # 0.0 - 1.0, target floor for boosted colors
ignore_saturation=0.25   # 0.0 - 1.0, colors below this are treated as
                         # intentional white/near-white and left untouched

r=$((16#${color:0:2}))
g=$((16#${color:2:2}))
b=$((16#${color:4:2}))

read -r changed saturation color <<< "$(awk -v r="$r" -v g="$g" -v b="$b" -v min_s="$min_saturation" -v ignore_s="$ignore_saturation" 'BEGIN {
    rn = r/255; gn = g/255; bn = b/255
    max = rn; if (gn > max) max = gn; if (bn > max) max = bn
    min = rn; if (gn < min) min = gn; if (bn < min) min = bn
    delta = max - min
    v = max
    s = (max == 0) ? 0 : delta/max

    if (delta == 0) h = 0
    else if (max == rn) h = 60 * (((gn - bn) / delta))
    else if (max == gn) h = 60 * (((bn - rn) / delta) + 2)
    else                h = 60 * (((rn - gn) / delta) + 4)
    if (h < 0) h += 360

    s_orig = s

    if (delta > 0 && s >= ignore_s && s < min_s) {
        changed = 1
        s = min_s
    } else {
        changed = 0
    }

    c = v * s
    hh = h / 60
    k = hh - 2 * int(hh / 2)
    xabs = k - 1; if (xabs < 0) xabs = -xabs
    x = c * (1 - xabs)
    m = v - c

    if (h < 60)        { rp = c; gp = x; bp = 0 }
    else if (h < 120)  { rp = x; gp = c; bp = 0 }
    else if (h < 180)  { rp = 0; gp = c; bp = x }
    else if (h < 240)  { rp = 0; gp = x; bp = c }
    else if (h < 300)  { rp = x; gp = 0; bp = c }
    else               { rp = c; gp = 0; bp = x }

    rr = int((rp + m) * 255 + 0.5)
    gg = int((gp + m) * 255 + 0.5)
    bb = int((bp + m) * 255 + 0.5)
    if (rr > 255) rr = 255; if (gg > 255) gg = 255; if (bb > 255) bb = 255
    if (rr < 0) rr = 0; if (gg < 0) gg = 0; if (bb < 0) bb = 0

    printf "%d %.3f %02x%02x%02x\n", changed, s_orig, rr, gg, bb
}')"

echo "Input color #$1 saturation: $(awk -v s="$saturation" 'BEGIN { printf "%.0f%%", s * 100 }')"

if [ "$changed" -eq 1 ]; then
    echo "Color too desaturated for LEDs, boosted saturation to #$color"
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