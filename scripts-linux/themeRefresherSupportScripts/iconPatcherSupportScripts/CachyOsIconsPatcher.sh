#!/usr/bin/env bash

# org.cachyos.hello — replace teal colors with accent + lighter highlight
patch_cachyos_hello_icon() {
    if command -v cachyos-hello >/dev/null 2>&1; then
python3 - << EOF
import colorsys

def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c*2 for c in h)
    return tuple(int(h[i:i+2], 16)/255 for i in (0, 2, 4))

def rgb_to_hex(r, g, b):
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

r, g, b = hex_to_rgb("$accent")
h, s, v = colorsys.rgb_to_hsv(r, g, b)
hr, hg, hb = colorsys.hsv_to_rgb(h, max(0, s - 0.3), min(1, v + 0.25))
highlight = rgb_to_hex(hr, hg, hb)

with open("/usr/share/icons/hicolor/scalable/apps/org.cachyos.hello.svg", "r") as f:
    content = f.read()
for old in ["#008066", "#0fc", "#0a8"]:
    content = content.replace(old, "$accent")
content = content.replace("#0cf", highlight)
with open("$iconThemeDir/apps/scalable/org.cachyos.hello.svg", "w") as f:
    f.write(content)
print(f"CachyOS icon patched (accent=$accent, highlight={highlight})")
EOF
        patch_desktop_icon "org.cachyos.hello" "*cachyos*hello*.desktop" "org.cachyos.hello.desktop"
    fi
}

# CachyOS Kernel Manager — ships PNG-only icons (16/22/32/44px), no scalable
# SVG upstream, so we can't sed-swap hex codes the way patch_cachyos_hello_icon
# does. Artwork is effectively single-hue (a green gradient with anti-aliased
# edges), so ImageMagick's -colorize 100% flattens it to the accent color
# while preserving the alpha/anti-aliasing shape — no HSV shading needed.
patch_cachyos_kernel_manager_icon() {
    if command -v cachyos-kernel-manager >/dev/null 2>&1 && { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }; then
        local tool="convert"
        command -v magick >/dev/null 2>&1 && tool="magick"
        local patched=0
        for size in 16 22 32 44; do
            src="/usr/share/icons/hicolor/${size}x${size}/apps/org.cachyos.KernelManager.png"
            dst="$iconThemeDir/apps/$size/cachyos-kernel-manager.png"
            if [ -f "$src" ]; then
                "$tool" "$src" -fill "$accent" -colorize 100% "$dst"
                patched=1
            fi
        done
        if [ "$patched" -eq 1 ]; then
            echo "CachyOS Kernel Manager icon patched"
            patch_desktop_icon "cachyos-kernel-manager" "org.cachyos.KernelManager.desktop" "*cachyos*kernel*manager*.desktop"
        else
            echo "  no CachyOS Kernel Manager icon files found to patch"
        fi
    fi
}