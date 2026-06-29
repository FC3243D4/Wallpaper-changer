#!/usr/bin/env bash
# iconPatcher.sh
# Patches icon SVGs in breeze-dark-accent with the accent color.
# Usage: iconPatcher.sh <hex_color>
# Example: iconPatcher.sh a986d3

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"

mkdir -p "$ICON_DIR/apps/16" "$ICON_DIR/apps/22" "$ICON_DIR/apps/24" \
         "$ICON_DIR/apps/32" "$ICON_DIR/apps/48" "$ICON_DIR/apps/64" \
         "$ICON_DIR/apps/scalable"

# Folder icons
for size in 16 22 24 32 48 64 96; do
    src="/usr/share/icons/breeze-dark/places/$size/folder.svg"
    dst="$ICON_DIR/places/$size/folder.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
done
src="/usr/share/icons/breeze-dark/mimetypes/64/inode-directory.svg"
dst="$ICON_DIR/mimetypes/64/inode-directory.svg"
[ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"

# system-file-manager
for size in 16 22 24 32 48 64; do
    src="/usr/share/icons/breeze-dark/apps/$size/system-file-manager.svg"
    dst="$ICON_DIR/apps/$size/system-file-manager.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
done

# preferences-system
for size in 16 32 48; do
    src="/usr/share/icons/breeze-dark/apps/$size/preferences-system.svg"
    dst="$ICON_DIR/apps/$size/preferences-system.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
done

# org.kde.dolphin — patch ColorScheme-Highlight (multiline)
python3 - << EOF
import re
with open('/usr/share/icons/hicolor/scalable/apps/org.kde.dolphin.svg', 'r') as f:
    content = f.read()
content = re.sub(
    r'(\.ColorScheme-Highlight\s*\{[^}]*color:)\s*#[0-9a-fA-F]+',
    r'\g<1> $accent',
    content,
    flags=re.DOTALL
)
with open('$ICON_DIR/apps/scalable/org.kde.dolphin.svg', 'w') as f:
    f.write(content)
print('Dolphin icon patched')
EOF

# org.cachyos.hello — replace teal colors with accent + lighter highlight
python3 - << EOF
import colorsys

def hex_to_rgb(h):
    h = h.lstrip('#')
    if len(h) == 3:
        h = ''.join(c*2 for c in h)
    return tuple(int(h[i:i+2], 16)/255 for i in (0, 2, 4))

def rgb_to_hex(r, g, b):
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

r, g, b = hex_to_rgb('$accent')
h, s, v = colorsys.rgb_to_hsv(r, g, b)
hr, hg, hb = colorsys.hsv_to_rgb(h, max(0, s - 0.3), min(1, v + 0.25))
highlight = rgb_to_hex(hr, hg, hb)

with open('/usr/share/icons/hicolor/scalable/apps/org.cachyos.hello.svg', 'r') as f:
    content = f.read()
for old in ['#008066', '#0fc', '#0a8']:
    content = content.replace(old, '$accent')
content = content.replace('#0cf', highlight)
with open('$ICON_DIR/apps/scalable/org.cachyos.hello.svg', 'w') as f:
    f.write(content)
print(f'CachyOS icon patched (accent=$accent, highlight={highlight})')
EOF

# Clear icon cache
rm -f "$HOME/.cache/icon-cache.kcache"
kbuildsycoca6 --noincremental 2>/dev/null

echo "Icons patched with $accent"
