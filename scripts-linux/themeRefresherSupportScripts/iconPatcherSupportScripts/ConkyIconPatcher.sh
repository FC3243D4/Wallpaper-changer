#!/usr/bin/env bash

# Conky logomark — multi-tone + embedded raster retinting
patch_conky_icon() {
    src="$iconsDir/conky_base_icon.svg"
    if [ -f "$src" ] && command -v conky >/dev/null 2>&1; then
        python3 - << EOF
import colorsys, re, base64, io

def hex_to_hsv(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return "#{:02x}{:02x}{:02x}".format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
dark   = hsv_to_hex(base_h, base_s, max(0, base_v - 0.15))
darker = hsv_to_hex(base_h, base_s, max(0, base_v - 0.35))
light  = hsv_to_hex(base_h, max(0, base_s - 0.35), min(1, base_v + 0.25))
mid    = "$accent"

with open("$src", "r") as f:
    svg = f.read()

svg = svg.replace("#B19DCB", light)   # st0 — background quad
svg = svg.replace("#666699", mid)     # st1 — blue-violet bars (40% opacity)
svg = svg.replace("#583494", dark)    # st2 — main solid "C" ring
svg = svg.replace("#3D296D", darker)  # st3 — dark accent rect (40% opacity)

try:
    from PIL import Image, ImageOps
    m = re.search(r'xlink:href="data:image/png;base64,([^"]+)"', svg)
    if m:
        png_bytes = base64.b64decode(m.group(1))
        im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
        r, g, b, a = im.split()
        gray = Image.merge("RGB", (r, g, b)).convert("L")
        tinted = ImageOps.colorize(gray, black="#000000", white=mid).convert("RGBA")
        tinted.putalpha(a)
        buf = io.BytesIO()
        tinted.save(buf, format="PNG")
        new_b64 = base64.b64encode(buf.getvalue()).decode()
        svg = svg[:m.start(1)] + new_b64 + svg[m.end(1):]
        print("  embedded raster retinted")
    else:
        print("  no embedded raster found (unexpected)")
except ImportError:
    print("  python3-pillow not found — embedded raster left unrecolored")

with open("$iconThemeDir/apps/scalable/conky.svg", "w") as f:
    f.write(svg)
print(f"Conky icon patched (dark={dark}, mid={mid}, light={light}, darker={darker})")
EOF

        patch_desktop_icon "conky" "conky.desktop" "*conky*.desktop"
    fi
}