#!/usr/bin/env bash
# iconPatcher.sh
# Patches icon SVGs in breeze-dark-accent with the accent color.
# Usage: iconPatcher.sh <hex_color>
#
# Every icon/utility lives in its own function below.

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

patch_folder_icons() {
    for size in 16 22 24 32 48 64 96; do
        src="/usr/share/icons/breeze-dark/places/$size/folder.svg"
        dst="$ICON_DIR/places/$size/folder.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

patch_inode_directory_icon() {
    src="/usr/share/icons/breeze-dark/mimetypes/64/inode-directory.svg"
    dst="$ICON_DIR/mimetypes/64/inode-directory.svg"
    [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
}

patch_system_file_manager_icon() {
    for size in 16 22 24 32 48 64; do
        src="/usr/share/icons/breeze-dark/apps/$size/system-file-manager.svg"
        dst="$ICON_DIR/apps/$size/system-file-manager.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

patch_preferences_system_icon() {
    for size in 16 32 48; do
        src="/usr/share/icons/breeze-dark/apps/$size/preferences-system.svg"
        dst="$ICON_DIR/apps/$size/preferences-system.svg"
        [ -f "$src" ] && sed "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$src" > "$dst"
    done
}

# org.kde.dolphin — patch ColorScheme-Highlight (multiline)
patch_dolphin_icon() {
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
}

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
with open("$ICON_DIR/apps/scalable/org.cachyos.hello.svg", "w") as f:
    f.write(content)
print(f"CachyOS icon patched (accent=$accent, highlight={highlight})")
EOF
        patch_desktop_icon "org.cachyos.hello" "*cachyos*hello*.desktop" "org.cachyos.hello.desktop"
    fi
}

patch_vscode_icon() {
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
}

patch_sourcegit_icon() {
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
}

# Tray icon: deliberately NOT accent-colored. Vesktop's tray icon only
# visibly refreshes when the icon is re-selected through its own UI, not
# on file/settings changes from outside — so a plain, static white icon
# (that never needs re-selecting) is more reliable than chasing per-accent
# recoloring here. Requires rsvg-convert (SVG rasterize) and ImageMagick
# (badge compositing). Called from patch_discord_vesktop_icons.
patch_vesktop_tray_icon() {
    local src="$1"
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
}

patch_discord_vesktop_icons() {
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
            patch_vesktop_tray_icon "$src"
        fi
    fi
}

# Patches for any recognized terminal emulator installed
patch_terminal_icons() {
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
}

patch_zen_browser_icon() {
    src="$ICONS/zen_browser_base_icon.svg"
    if [ -f "$src" ] && command -v zen-browser >/dev/null 2>&1; then
        sed "s/fill=\"currentColor\"/fill=\"$accent\"/" "$src" > "$ICON_DIR/apps/scalable/zen.svg"
        echo "Zen Browser icon patched"
        patch_desktop_icon "zen" "zen.desktop" "*zen*browser*.desktop" "*zen-browser*.desktop"
    fi
}

patch_firefox_icon() {
    src="$ICONS/firefox_base_icon.svg"
    if [ -f "$src" ] && command -v firefox >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/firefox.svg"
        echo "Firefox icon patched"
        patch_desktop_icon "firefox" "firefox.desktop" "*firefox*.desktop"
    fi
}

patch_brave_icon() {
    src="$ICONS/brave_base_icon.svg"
    if [ -f "$src" ] && { command -v brave-browser >/dev/null 2>&1 || command -v brave >/dev/null 2>&1; }; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/brave.svg"
        echo "Brave icon patched"
        patch_desktop_icon "brave" "brave-browser.desktop" "brave.desktop" "*brave*.desktop"
    fi
}

patch_chrome_icon() {
    src="$ICONS/chrome_base_icon.svg"
    if [ -f "$src" ] && { command -v google-chrome-stable >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1; }; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/chrome.svg"
        echo "Chrome icon patched"
        patch_desktop_icon "chrome" "google-chrome.desktop" "*google-chrome*.desktop" "chromium.desktop" "*chromium*.desktop"
    fi
}

patch_steam_icon() {
    src="$ICONS/steam_base_icon.svg"
    if [ -f "$src" ] && command -v steam >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/steam.svg"
        echo "Steam icon patched"
        patch_desktop_icon "steam" "steam.desktop" "*steam*.desktop"
    fi
}

# Gimp icon (Flatpak)
patch_gimp_icon() {
    src="$ICONS/gimp_base_icon.svg"
    if [ -f "$src" ] && command -v org.gimp.GIMP >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/gimp.svg"
        echo "Gimp icon patched"
        patch_desktop_icon "gimp" "org.gimp.GIMP.desktop"
    fi
}

# Nativmix icon — three-tone
patch_nativmix_icon() {
    src="$ICONS/nativmix_base_icon.svg"
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

with open("$ICON_DIR/apps/scalable/nativmix.svg", "w") as f:
    f.write(svg)
print(f"Nativmix icon patched (bg={background}, tracks={tracks}, knobs={knobs})")
EOF
        patch_desktop_icon "nativmix" "nativmix.desktop" "*nativmix*.desktop"
    fi
}

patch_ferdium_icon() {
    src="$ICONS/ferdium_base_icon.svg"
    if [ -f "$src" ] && command -v ferdium >/dev/null 2>&1; then
        sed "s|<svg xmlns=\"http://www.w3.org/2000/svg\"|<svg fill=\"$accent\" xmlns=\"http://www.w3.org/2000/svg\"|" "$src" > "$ICON_DIR/apps/scalable/ferdium.svg"
        echo "Ferdium icon patched"
        patch_desktop_icon "ferdium" "ferdium.desktop" "*ferdium*.desktop"
    fi
}

patch_piper_icon() {
    src="$ICONS/piper_base_icon.svg"
    if [ -f "$src" ] && command -v piper >/dev/null 2>&1; then
        sed "s|<svg id=\"logosandtypes_com\" data-name=\"logosandtypes com\" xmlns=\"http://www.w3.org/2000/svg\"|<svg id=\"logosandtypes_com\" data-name=\"logosandtypes com\" fill=\"$accent\" xmlns=\"http://www.w3.org/2000/svg\"|" "$src" > "$ICON_DIR/apps/scalable/piper.svg"
        echo "Piper icon patched"
        patch_desktop_icon "piper" "piper.desktop" "*piper*.desktop"
    fi
}

# OrcaSlicer icon — three-tone: the two near-black shapes collapse to one
# accent-tinted dark shade, the brand teal maps to full accent, and white
# is left untouched as a highlight.
patch_orcaslicer_icon() {
    src="$ICONS/orcaslicer_base_icon.svg"
    if [ -f "$src" ] && command -v orca-slicer >/dev/null 2>&1; then
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
dark = hsv_to_hex(base_h, base_s, 0.16)
teal = "$accent"

with open("$src", "r") as f:
    svg = f.read()
svg = svg.replace("#292826", dark)
svg = svg.replace("#262523", dark)
svg = svg.replace("#009789", teal)

with open("$ICON_DIR/apps/scalable/orcaslicer.svg", "w") as f:
    f.write(svg)
print(f"OrcaSlicer icon patched (dark={dark}, teal={teal})")
EOF
        patch_desktop_icon "orcaslicer" "orca-slicer.desktop" "*orcaslicer*.desktop" "*orca-slicer*.desktop"
    fi
}

patch_plasma_system_monitor_icon() {
    src="$ICONS/plasma_system_monitor_base_icon.svg"
    if [ -f "$src" ] && command -v plasma-systemmonitor >/dev/null 2>&1; then
        sed "s/gray/$accent/g" "$src" > "$ICON_DIR/apps/scalable/plasma-system-monitor.svg"
        echo "Plasma System Monitor icon patched"
        patch_desktop_icon "plasma-system-monitor" "plasma-systemmonitor.desktop" "*plasma-systemmonitor*.desktop"
    fi
}

# OnlyOffice icon — no explicit fill (default black), inject accent
patch_onlyoffice_icon() {
    src="$ICONS/onlyoffice_base_icon.svg"
    if [ -f "$src" ] && command -v onlyoffice-desktopeditors >/dev/null 2>&1; then
        sed "s|<svg role=\"img\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\">|<svg role=\"img\" fill=\"$accent\" viewBox=\"0 0 24 24\" xmlns=\"http://www.w3.org/2000/svg\">|" "$src" > "$ICON_DIR/apps/scalable/onlyoffice.svg"
        echo "OnlyOffice icon patched"
        patch_desktop_icon "onlyoffice" "onlyoffice-desktopeditors.desktop" "*onlyoffice*.desktop"
    fi
}

# OBS studio icon (Flatpak) — tightened glob to avoid matching unrelated
# .desktop files containing "obs" as a substring (e.g. "Obscur")
patch_obs_studio_icon() {
    src="$ICONS/obs_base_icon.svg"
    if [ -f "$src" ] && command -v com.obsproject.Studio >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/obs-studio.svg"
        echo "OBS Studio icon patched"
        patch_desktop_icon "obs-studio" "com.obsproject.Studio.desktop"
    fi
}

# DaVinci Resolve icon — binary lives outside $PATH, check the real location
patch_davinci_resolve_icon() {
    src="$ICONS/davinci_resolve_base_icon.svg"
    if [ -f "$src" ] && [ -x "/opt/resolve/bin/resolve" ]; then
        sed "s/#FFFFFF/$accent/g" "$src" > "$ICON_DIR/apps/scalable/davinci-resolve.svg"
        echo "DaVinci Resolve icon patched"
        patch_desktop_icon "davinci-resolve" "DaVinciResolve.desktop"
    fi
}

patch_kde_connect_icon() {
    src="$ICONS/kde_connect_base_icon.svg"
    if [ -f "$src" ] && command -v kdeconnect-app >/dev/null 2>&1; then
        sed "s/none/$accent/g" "$src" > "$ICON_DIR/apps/scalable/kdeconnect.svg"
        echo "KDE Connect icon patched"
        patch_desktop_icon "kdeconnect" "kdeconnect-app.desktop" "*kdeconnect*app*.desktop"
    fi
}

patch_nwg_look_icon() {
    src="$ICONS/nwg-look_base_icon.svg"
    if [ -f "$src" ] && command -v nwg-look >/dev/null 2>&1; then
        sed "s/#00aad4/$accent/g" "$src" > "$ICON_DIR/apps/scalable/nwg-look.svg"
        echo "nwg-look icon patched"
        patch_desktop_icon "nwg-look" "nwg-look.desktop" "*nwg-look*.desktop"
    fi
}

patch_vial_icon() {
    src="$ICONS/vial_base_icon.svg"
    if [ -f "$src" ] && command -v Vial >/dev/null 2>&1; then
        sed "s/none/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vial.svg"
        echo "Vial icon patched"
        patch_desktop_icon "vial" "Vial.desktop"
    fi
}

# Network icon — shared across Advanced Network Configuration and the
# three Avahi service browsers (SSH/VNC/Zeroconf), all base-system
# utilities without one clean binary to gate on individually.
patch_network_icons() {
    src="$ICONS/network_base_icon.svg"
    if [ -f "$src" ]; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/network.svg"
        echo "Network icon patched"
        patch_desktop_icon "network" "nm-connection-editor.desktop"
        patch_desktop_icon "network" "avahi-discover.desktop"
        patch_desktop_icon "network" "bssh.desktop"
        patch_desktop_icon "network" "bvnc.desktop"
    fi
}

patch_arduino_ide_icon() {
    src="$ICONS/arduino_base_icon.svg"
    if [ -f "$src" ] && command -v arduino-ide >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/arduino.svg"
        echo "Arduino IDE icon patched"
        patch_desktop_icon "arduino" "arduino-ide.desktop" "*arduino*.desktop"
    fi
}

patch_ark_icon() {
    src="$ICONS/zip_base_icon.svg"
    if [ -f "$src" ] && command -v ark >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/ark.svg"
        echo "Ark icon patched"
        patch_desktop_icon "ark" "ark.desktop" "*ark*.desktop"
    fi
}

# Blackmagic RAW Player icon — bundled with DaVinci Resolve, binary
# outside $PATH under /opt/resolve/
patch_blackmagic_raw_player_icon() {
    src="$ICONS/player_base_icon.svg"
    if [ -f "$src" ] && [ -x "/opt/resolve/BlackmagicRAWPlayer/BlackmagicRAWPlayer" ]; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/blackmagic-raw-player.svg"
        echo "Blackmagic RAW Player icon patched"
        patch_desktop_icon "blackmagic-raw-player" "blackmagicraw-player.desktop"
    fi
}

# Blackmagic RAW Speed Test icon — same situation, bundled with Resolve
patch_blackmagic_raw_speedtest_icon() {
    src="$ICONS/speedtest_base_icon.svg"
    if [ -f "$src" ] && [ -x "/opt/resolve/BlackmagicRAWSpeedTest/BlackmagicRAWSpeedTest" ]; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/blackmagic-raw-speedtest.svg"
        echo "Blackmagic RAW Speed Test icon patched"
        patch_desktop_icon "blackmagic-raw-speedtest" "blackmagicraw-speedtest.desktop"
    fi
}

patch_blender_icon() {
    src="$ICONS/blender_base_icon.svg"
    if [ -f "$src" ] && command -v blender >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/blender.svg"
        echo "Blender icon patched"
        patch_desktop_icon "blender" "blender.desktop" "*blender*.desktop"
    fi
}

cleanup_icon_cache() {
    rm -f "$HOME/.cache/icon-cache.kcache"
    kbuildsycoca6 --noincremental 2>/dev/null
}

# ---- Run everything, in order ----
patch_folder_icons
patch_inode_directory_icon
patch_system_file_manager_icon
patch_preferences_system_icon
patch_dolphin_icon
patch_cachyos_hello_icon
patch_vscode_icon
patch_sourcegit_icon
patch_discord_vesktop_icons
patch_terminal_icons
patch_zen_browser_icon
patch_firefox_icon
patch_brave_icon
patch_chrome_icon
patch_steam_icon
patch_gimp_icon
patch_nativmix_icon
patch_ferdium_icon
patch_piper_icon
patch_orcaslicer_icon
patch_plasma_system_monitor_icon
patch_onlyoffice_icon
patch_obs_studio_icon
patch_davinci_resolve_icon
patch_kde_connect_icon
patch_nwg_look_icon
patch_vial_icon
patch_network_icons
patch_arduino_ide_icon
patch_ark_icon
patch_blackmagic_raw_player_icon
patch_blackmagic_raw_speedtest_icon
patch_blender_icon
cleanup_icon_cache

echo "Icons patched with $accent"