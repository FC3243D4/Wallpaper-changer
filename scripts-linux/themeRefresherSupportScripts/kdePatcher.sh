#!/usr/bin/env bash
# kdePatcher.sh
# Patches KDE color schemes and kdeglobals with the accent color.
# Usage: kdePatcher.sh <hex_color>
# Example: kdePatcher.sh a986d3

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))

# 1. Patch BreezeDark.colors (always from clean base, single awk pass)
BREEZE_COLORS="$HOME/.local/share/color-schemes/BreezeDark.colors"
BREEZE_COLORS_BASE="${BREEZE_COLORS}.base"

[ ! -f "$BREEZE_COLORS_BASE" ] && [ -f "$BREEZE_COLORS" ] && cp "$BREEZE_COLORS" "$BREEZE_COLORS_BASE"

if [ -f "$BREEZE_COLORS_BASE" ]; then
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:View\]/      { in_view=1; in_sel=0 }
        /^\[Colors:Selection\]/ { in_sel=1;  in_view=0 }
        /^\[/ && !/^\[Colors:View\]/ && !/^\[Colors:Selection\]/ { in_view=0; in_sel=0 }
        /^DecorationFocus=/     { print "DecorationFocus=" rgb; next }
        /^DecorationHover=/     { print "DecorationHover=" rgb; next }
        in_view && /^ForegroundActive=/ { print "ForegroundActive=" rgb; next }
        in_sel  && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$BREEZE_COLORS_BASE" > "$BREEZE_COLORS"
fi

# 2. Patch WallpaperAccent.colors (used by plasmashell for taskbar highlight)
WALLPAPER_ACCENT="$HOME/.local/share/color-schemes/WallpaperAccent.colors"
WALLPAPER_ACCENT_BASE="${WALLPAPER_ACCENT}.base"

[ ! -f "$WALLPAPER_ACCENT_BASE" ] && [ -f "$WALLPAPER_ACCENT" ] && cp "$WALLPAPER_ACCENT" "$WALLPAPER_ACCENT_BASE"

if [ -f "$WALLPAPER_ACCENT_BASE" ]; then
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:Selection\]/ { in_sel=1 }
        /^\[/ && !/^\[Colors:Selection\]/ { in_sel=0 }
        /^DecorationFocus=/  { print "DecorationFocus=" rgb; next }
        /^DecorationHover=/  { print "DecorationHover=" rgb; next }
        /^AccentColor=/      { print "AccentColor=" rgb; next }
        in_sel && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$WALLPAPER_ACCENT_BASE" > "$WALLPAPER_ACCENT"
fi

# 3. Patch kdeglobals
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "DecorationFocus"     "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "DecorationHover"     "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "ForegroundActive"    "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundNormal"    "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundAlternate" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "General"          --key "AccentColor"         "$R,$G,$B"
qdbus6 org.kde.KGlobalSettings /KGlobalSettings notifyChange 0 0 2>/dev/null || true

# Force plasmashell to reload accent color
plasma-apply-colorscheme WallpaperAccent 2>/dev/null || true
plasma-apply-colorscheme BreezeDark 2>/dev/null || true

echo "KDE patched with $R,$G,$B"
