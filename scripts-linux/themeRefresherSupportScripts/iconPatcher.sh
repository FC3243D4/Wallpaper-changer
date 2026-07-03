#!/usr/bin/env bash
# iconPatcher.sh
# Patches icon SVGs in breeze-dark-accent with the accent color.
# Usage: iconPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"
SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
ICONS="$SUPPORT/svg"

mkdir -p "$ICON_DIR/apps/16" "$ICON_DIR/apps/22" "$ICON_DIR/apps/24" \
         "$ICON_DIR/apps/32" "$ICON_DIR/apps/48" "$ICON_DIR/apps/64" \
         "$ICON_DIR/apps/scalable"

DESKTOP_DIRS=(
    "$HOME/.local/share/applications"
    "/usr/share/applications"
    "/usr/local/share/applications"
    "/var/lib/flatpak/exports/share/applications"
    "$HOME/.local/share/flatpak/exports/share/applications"
)

# patch_desktop_icon <icon_name> <glob_pattern> [more_patterns...]
# Finds .desktop files matching the given glob(s) in known application dirs.
# If Icon= doesn't already match icon_name, creates/updates a user-level
# override in ~/.local/share/applications (XDG standard: user overrides win
# over system files, no root needed, survives package updates).
patch_desktop_icon() {
    local icon_name="$1"; shift
    local patterns=("$@")
    local matched=0
    shopt -s nullglob nocaseglob
    for dir in "${DESKTOP_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for pattern in "${patterns[@]}"; do
            for file in "$dir"/$pattern; do
                [ -f "$file" ] || continue
                matched=1
                local current
                current=$(grep -m1 "^Icon=" "$file" | cut -d= -f2-)
                if [ "$current" != "$icon_name" ]; then
                    local base="$(basename "$file")"
                    local override="$HOME/.local/share/applications/$base"
                    mkdir -p "$HOME/.local/share/applications"
                    [ -f "$override" ] || cp "$file" "$override"
                    if grep -q "^Icon=" "$override"; then
                        sed -i "s|^Icon=.*|Icon=$icon_name|" "$override"
                    else
                        echo "Icon=$icon_name" >> "$override"
                    fi
                    echo "  .desktop updated: $base (Icon: ${current:-<none>} -> $icon_name)"
                fi
            done
        done
    done
    shopt -u nullglob nocaseglob
    [ "$matched" -eq 0 ] && echo "  no .desktop file found for $icon_name"
}

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
if command -v dolphin >/dev/null 2>&1; then
python3 - << EOF
import re
with open("/usr/share/icons/hicolor/scalable/apps/org.kde.dolphin.svg", "r") as f:
    content = f.read()
content = re.sub(
    r"(\.ColorScheme-Highlight\s*\{[^}]*color:)\s*#[0-9a-fA-F]+",
    r"\g<1> $accent",
    content,
    flags=re.DOTALL
)
with open("$ICON_DIR/apps/scalable/org.kde.dolphin.svg", "w") as f:
    f.write(content)
print("Dolphin icon patched")
EOF
patch_desktop_icon "org.kde.dolphin" "org.kde.dolphin.desktop"
fi

# org.cachyos.hello — replace teal colors with accent + lighter highlight
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
with open("$ICON_DIR/apps/scalable/org.cachyos.hello.svg", "w") as f:
    f.write(content)
print(f"CachyOS icon patched (accent=$accent, highlight={highlight})")
EOF
patch_desktop_icon "org.cachyos.hello" "*cachyos*hello*.desktop" "org.cachyos.hello.desktop"
fi

# VS Code icon
src="$ICONS/vscode_base_icon.svg"
if [ -f "$src" ] && command -v code >/dev/null 2>&1; then
    python3 - << EOF
import colorsys

def hex_to_hsv(h):
    h = h.lstrip("#")
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return "#{:02X}{:02X}{:02X}".format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
dark  = hsv_to_hex(base_h, base_s, max(0, base_v - 0.15))
mid   = hsv_to_hex(base_h, base_s, base_v)
light = hsv_to_hex(base_h, max(0, base_s - 0.2), min(1, base_v + 0.15))

with open("$src", "r") as f:
    svg = f.read()
svg = svg.replace("#0065A9", dark)
svg = svg.replace("#007ACC", mid)
svg = svg.replace("#1F9CF0", light)

with open("$ICON_DIR/apps/scalable/vscode.svg", "w") as f:
    f.write(svg)
print(f"VSCode icon patched (dark={dark}, mid={mid}, light={light})")
EOF
patch_desktop_icon "vscode" "code.desktop" "visual-studio-code.desktop" "*visual-studio-code*.desktop"
fi

# SourceGit icon
src="$ICONS/sourcegit_base_icon.svg"
if [ -f "$src" ] && command -v sourcegit >/dev/null 2>&1; then
    python3 - << EOF
with open("$src", "r") as f:
    content = f.read()
content = content.replace("#F05133", "$accent")
with open("$ICON_DIR/apps/scalable/sourcegit.svg", "w") as f:
    f.write(content)
print("SourceGit icon patched")
EOF
patch_desktop_icon "sourcegit" "sourcegit.desktop" "*sourcegit*.desktop" "*source-git*.desktop"
fi

# Discord / Vesktop icon (shared source, separate destinations)
src="$ICONS/discord_base_icon.svg"
if [ -f "$src" ]; then
    if command -v discord >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/discord.svg"
        echo "Discord icon patched"
        patch_desktop_icon "discord" "discord.desktop" "com.discordapp.Discord.desktop"
    fi
    if command -v vesktop >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vesktop.svg"
        echo "Vesktop icon patched"
        patch_desktop_icon "vesktop" "vesktop.desktop" "*vesktop*.desktop"

        # Tray icon: deliberately NOT accent-colored. Vesktop's tray icon
        # only visibly refreshes when the icon is re-selected through its
        # own UI, not on file/settings changes from outside — so a plain,
        # static white icon (that never needs re-selecting) is more
        # reliable than chasing per-accent recoloring here. Requires
        # rsvg-convert (SVG rasterize) and ImageMagick (badge compositing).
        VESKTOP_SETTINGS="$HOME/.config/vesktop/settings.json"
        if command -v rsvg-convert >/dev/null 2>&1 && [ -f "$VESKTOP_SETTINGS" ]; then
            TRAY_DIR="$SUPPORT/tray-icons"
            mkdir -p "$TRAY_DIR"

            white_svg="$(mktemp --suffix=.svg)"
            sed "s/#000000/#ffffff/g" "$src" > "$white_svg"

            tray_png="$TRAY_DIR/vesktop-tray.png"
            rsvg-convert -w 256 -h 256 "$white_svg" -o "$tray_png"
            rm -f "$white_svg"
            echo "Vesktop tray icon generated (white)"

            # Unread-state variant: same white icon with a red notification
            # dot composited in the bottom-right corner.
            tray_png_unread="$TRAY_DIR/vesktop-tray-unread.png"
            if command -v magick >/dev/null 2>&1; then
                magick "$tray_png" -fill "#ed4245" -stroke none \
                    -draw "circle 200,56 200,16" "$tray_png_unread"
                echo "Vesktop tray icon (unread/red-dot) generated"
            elif command -v convert >/dev/null 2>&1; then
                convert "$tray_png" -fill "#ed4245" -stroke none \
                    -draw "circle 200,56 200,16" "$tray_png_unread"
                echo "Vesktop tray icon (unread/red-dot) generated"
            else
                echo "  ImageMagick not found — skipping unread-state tray icon"
            fi

            python3 - "$VESKTOP_SETTINGS" "$tray_png" << 'EOF'
import json
import sys

settings_path, tray_png = sys.argv[1], sys.argv[2]
with open(settings_path, "r") as f:
    data = json.load(f)

if data.get("trayIconPath") != tray_png:
    data["trayIconPath"] = tray_png
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=4)
    print("  trayIconPath updated (re-select it once in Vesktop's tray icon")
    print("  picker to force a visual refresh — see prior troubleshooting)")
EOF
        elif ! command -v rsvg-convert >/dev/null 2>&1; then
            echo "  rsvg-convert not found — skipping Vesktop tray icon (install librsvg for this)"
        fi
    fi
fi

# Terminal emulator icon(s) — patches for any recognized terminal emulator installed
src="$ICONS/terminal_base_icon.svg"
if [ -f "$src" ]; then
    for term in kitty alacritty wezterm foot ghostty konsole gnome-terminal terminator tilix xterm urxvt st xfce4-terminal deepin-terminal lxterminal; do
        if command -v "$term" >/dev/null 2>&1; then
            sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/$term.svg"
            echo "Terminal icon patched ($term)"
            patch_desktop_icon "$term" "$term.desktop" "*$term*.desktop"
        fi
    done
fi

# Zen Browser icon
src="$ICONS/zen_browser_base_icon.svg"
if [ -f "$src" ] && command -v zen-browser >/dev/null 2>&1; then
    sed "s/fill=\"currentColor\"/fill=\"$accent\"/" "$src" > "$ICON_DIR/apps/scalable/zen.svg"
    echo "Zen Browser icon patched"
    patch_desktop_icon "zen" "zen.desktop" "*zen*browser*.desktop" "*zen-browser*.desktop"
fi

# Firefox icon
src="$ICONS/firefox_base_icon.svg"
if [ -f "$src" ] && command -v firefox >/dev/null 2>&1; then
    sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/firefox.svg"
    echo "Firefox icon patched"
    patch_desktop_icon "firefox" "firefox.desktop" "*firefox*.desktop"
fi

# Brave icon
src="$ICONS/brave_base_icon.svg"
if [ -f "$src" ] && { command -v brave-browser >/dev/null 2>&1 || command -v brave >/dev/null 2>&1; }; then
    sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/brave.svg"
    echo "Brave icon patched"
    patch_desktop_icon "brave" "brave-browser.desktop" "brave.desktop" "*brave*.desktop"
fi

# Chrome icon
src="$ICONS/chrome_base_icon.svg"
if [ -f "$src" ] && { command -v google-chrome-stable >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1; }; then
    sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/chrome.svg"
    echo "Chrome icon patched"
    patch_desktop_icon "chrome" "google-chrome.desktop" "*google-chrome*.desktop" "chromium.desktop" "*chromium*.desktop"
fi

# Clear icon cache
rm -f "$HOME/.cache/icon-cache.kcache"
kbuildsycoca6 --noincremental 2>/dev/null

echo "Icons patched with $accent"