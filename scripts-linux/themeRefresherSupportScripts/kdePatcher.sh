#!/usr/bin/env bash
# kdePatcher.sh
# Patches KDE color schemes and kdeglobals with the accent color, then
# tells plasmashell to reload it.
# Usage: kdePatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

r=$((16#${color:0:2}))
g=$((16#${color:2:2}))
b=$((16#${color:4:2}))

# 1. Patch BreezeDark.colors (always regenerated from a clean base copy)
breezeColorsFile="$HOME/.local/share/color-schemes/BreezeDark.colors"
breezeColorsBaseFile="${breezeColorsFile}.base"

[ ! -f "$breezeColorsBaseFile" ] && [ -f "$breezeColorsFile" ] && cp "$breezeColorsFile" "$breezeColorsBaseFile"

if [ -f "$breezeColorsBaseFile" ]; then
    awk -v rgb="$r,$g,$b" '
        /^\[Colors:View\]/      { inView=1; inSel=0; inWin=0; inBtn=0 }
        /^\[Colors:Selection\]/ { inSel=1;  inView=0; inWin=0; inBtn=0 }
        /^\[Colors:Window\]/    { inWin=1;  inView=0; inSel=0; inBtn=0 }
        /^\[Colors:Button\]/    { inBtn=1;  inView=0; inSel=0; inWin=0 }
        /^\[/ && !/^\[Colors:View\]/ && !/^\[Colors:Selection\]/ && !/^\[Colors:Window\]/ && !/^\[Colors:Button\]/ { inView=0; inSel=0; inWin=0; inBtn=0 }
        (inView || inSel || inWin || inBtn) && /^DecorationFocus=/ { print "DecorationFocus=" rgb; next }
        (inView || inSel || inWin || inBtn) && /^DecorationHover=/ { print "DecorationHover=" rgb; next }
        inView && /^ForegroundActive=/ { print "ForegroundActive=" rgb; next }
        inSel  && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$breezeColorsBaseFile" > "$breezeColorsFile"
fi

# 2. Patch WallpaperAccent.colors (used by plasmashell for taskbar highlight)
wallpaperAccentFile="$HOME/.local/share/color-schemes/WallpaperAccent.colors"
wallpaperAccentBaseFile="${wallpaperAccentFile}.base"

[ ! -f "$wallpaperAccentBaseFile" ] && [ -f "$wallpaperAccentFile" ] && cp "$wallpaperAccentFile" "$wallpaperAccentBaseFile"

if [ -f "$wallpaperAccentBaseFile" ]; then
    awk -v rgb="$r,$g,$b" '
        /^\[Colors:Selection\]/ { inSel=1 }
        /^\[/ && !/^\[Colors:Selection\]/ { inSel=0 }
        /^DecorationFocus=/  { print "DecorationFocus=" rgb; next }
        /^DecorationHover=/  { print "DecorationHover=" rgb; next }
        /^AccentColor=/      { print "AccentColor=" rgb; next }
        inSel && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$wallpaperAccentBaseFile" > "$wallpaperAccentFile"
fi

# 3. Patch kdeglobals
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "DecorationFocus"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "DecorationHover"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:View"      --key "ForegroundActive"    "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "DecorationFocus"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "DecorationHover"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundNormal"    "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundAlternate" "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Window"    --key "DecorationFocus"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Window"    --key "DecorationHover"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Button"    --key "DecorationFocus"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "Colors:Button"    --key "DecorationHover"     "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "General"          --key "AccentColor"         "$r,$g,$b"
kwriteconfig6 --file kdeglobals --group "General"          --key "AccentColorFromWallpaper" "false"
qdbus6 org.kde.KGlobalSettings /KGlobalSettings notifyChange 0 0 2>/dev/null || true

# Force plasmashell to reload accent color
plasma-apply-colorscheme WallpaperAccent 2>/dev/null || true
plasma-apply-colorscheme BreezeDark 2>/dev/null || true

echo "KDE patched with $r,$g,$b"