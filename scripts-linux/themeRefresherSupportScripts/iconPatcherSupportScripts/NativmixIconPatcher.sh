#!/usr/bin/env bash

# Nativmix icon — three-tone
patch_nativmix_icon() {
    src="$iconsDir/nativmix_base_icon.svg"
    if [ -f "$src" ] && command -v nativmix >/dev/null 2>&1; then
        python3 - << EOF
import colorsys

def hex_to_hsv(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
background = hsv_to_hex(base_h, base_s, base_v)
tracks     = hsv_to_hex(base_h, base_s, max(0, base_v - 0.15))
knobs      = hsv_to_hex(base_h, max(0, base_s - 0.35), min(1, base_v + 0.3))

with open("$src", "r") as f:
    svg = f.read()
svg = svg.replace("#8c8c8c", background)
svg = svg.replace("#282828", tracks)
svg = svg.replace("#dcdcdc", knobs)

with open("$iconThemeDir/apps/scalable/nativmix.svg", "w") as f:
    f.write(svg)
print(f"Nativmix icon patched (bg={background}, tracks={tracks}, knobs={knobs})")
EOF
        patch_desktop_icon "nativmix" "nativmix.desktop" "*nativmix*.desktop"
    fi
}