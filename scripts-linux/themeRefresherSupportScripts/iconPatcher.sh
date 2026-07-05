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
         "$ICON_DIR/apps/32" "$ICON_DIR/apps/44" "$ICON_DIR/apps/48" \
         "$ICON_DIR/apps/64" "$ICON_DIR/apps/scalable"

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
            dst="$ICON_DIR/apps/$size/cachyos-kernel-manager.png"
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

patch_vscode_icon() {
    src="$ICONS/vscode_base_icon.svg"
    if [ -f "$src" ] && command -v code >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vscode.svg"
        echo "VS Code icon patched"
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
            sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/discord.svg"
            echo "Discord icon patched"
            patch_desktop_icon "discord" "discord.desktop" "com.discordapp.Discord.desktop"
        fi
        if command -v vesktop >/dev/null 2>&1; then
            sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vesktop.svg"
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
                sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/$term.svg"
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
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/firefox.svg"
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
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/chrome.svg"
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

patch_system_monitor_icon() {
    src="$ICONS/system_monitor_base_icon.svg"
    if [ -f "$src" ] && ( command -v plasma-systemmonitor >/dev/null 2>&1 || 
                          command -v gnome-system-monitor >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/system-monitor.svg"
        echo "Plasma System Monitor icon patched"
        patch_desktop_icon "system-monitor" "plasma-systemmonitor.desktop" "*plasma-systemmonitor*.desktop"
        patch_desktop_icon "system-monitor" "org.gnome.SystemMonitor.desktop" "*SystemMonitor*.desktop"
    fi
}

# OnlyOffice icon — no explicit fill (default black), inject accent
patch_onlyoffice_icon() {
    src="$ICONS/onlyoffice_base_icon.svg"
    if [ -f "$src" ] && command -v onlyoffice-desktopeditors >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/onlyoffice.svg"
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
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/kdeconnect.svg"
        echo "KDE Connect icon patched"
        patch_desktop_icon "kdeconnect" "kdeconnect-app.desktop" "*kdeconnect*app*.desktop"
    fi
}

patch_nwg_displays_icon() {
    src="$ICONS/nwg-displays_base_icon.svg"
    if [ -f "$src" ] && command -v nwg-displays >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/nwg-displays.svg"
        echo "nwg-displays icon patched"
        patch_desktop_icon "nwg-displays" "nwg-displays.desktop" "*nwg-displays*.desktop"
    fi
}

patch_vial_icon() {
    src="$ICONS/vial_base_icon.svg"
    if [ -f "$src" ] && command -v Vial >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vial.svg"
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
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/network.svg"
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
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/ark.svg"
        echo "Ark icon patched"
        patch_desktop_icon "ark" "ark.desktop" "*ark*.desktop"
    fi
}

# Player icon
patch_player_icon() {
    src="$ICONS/player_base_icon.svg"
    if [ -f "$src" ] && ( [ -x "/opt/resolve/BlackmagicRAWPlayer/BlackmagicRAWPlayer" ] || command -v mpv >/dev/null 2>&1 || 
                                                                                           command -v vlc >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/player.svg"
        echo "Player icon patched"
        patch_desktop_icon "player" "blackmagicraw-player.desktop"
        patch_desktop_icon "player" "*mpv*.desktop"
        patch_desktop_icon "player" "*vlc*.desktop"
    fi
}

# Generic settings icon
# for DaVinci Control Panels Setup and grub-customizer
patch_generic_settings_icon() {
    src="$ICONS/settings_base_icon.svg"
    if [ -f "$src" ] && ( [ -x "/opt/resolve/DaVinci Control Panels Setup/DaVinci Control Panels Setup" ] || command -v grub-customizer >/dev/null 2>&1 || 
                                                                                                             command -v yad >/dev/null 2>&1 || 
                                                                                                             command -v lstopo >/dev/null 2>&1 || 
                                                                                                             command -v nvtop >/dev/null 2>&1 || 
                                                                                                             command -v qv4l2 >/dev/null 2>&1 || 
                                                                                                             command -v qvidcap >/dev/null 2>&1 || 
                                                                                                             command -v assistant6 >/dev/null 2>&1 || 
                                                                                                             command -v linguist6 >/dev/null 2>&1 || 
                                                                                                             command -v qdbusviewer6 >/dev/null 2>&1 || 
                                                                                                             command -v scx-manager >/dev/null 2>&1 || 
                                                                                                             command -v uuctl >/dev/null 2>&1 || 
                                                                                                             command -v winetricks >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/settings.svg"
        echo "Generic settings icon patched"
        patch_desktop_icon "settings" "DaVinciControlPanelsSetup.desktop"
        patch_desktop_icon "settings" "grub-customizer.desktop"
        patch_desktop_icon "settings" "*yad*.desktop"
        patch_desktop_icon "settings" "lstopo.desktop"
        patch_desktop_icon "settings" "nvtop.desktop"
        patch_desktop_icon "settings" "qv4l2.desktop"
        patch_desktop_icon "settings" "qvidcap.desktop"
        patch_desktop_icon "settings" "assistant.desktop"
        patch_desktop_icon "settings" "linguist.desktop"
        patch_desktop_icon "settings" "qdbusviewer.desktop"
        patch_desktop_icon "settings" "*scx-manager*.desktop"
        patch_desktop_icon "settings" "uuctl.desktop"
        patch_desktop_icon "settings" "winetricks.desktop"
        patch_desktop_icon "settings" "kdesystemsettings.desktop"
    fi
}

# Blackmagic RAW Speed Test icon — same situation, bundled with Resolve
patch_blackmagic_raw_speedtest_icon() {
    src="$ICONS/speedtest_base_icon.svg"
    if [ -f "$src" ] && [ -x "/opt/resolve/BlackmagicRAWSpeedTest/BlackmagicRAWSpeedTest" ]; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/blackmagic-raw-speedtest.svg"
        echo "Blackmagic RAW Speed Test icon patched"
        patch_desktop_icon "blackmagic-raw-speedtest" "blackmagicraw-speedtest.desktop"
    fi
}

patch_blender_icon() {
    src="$ICONS/blender_base_icon.svg"
    if [ -f "$src" ] && command -v blender >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/blender.svg"
        echo "Blender icon patched"
        patch_desktop_icon "blender" "blender.desktop" "*blender*.desktop"
    fi
}

patch_bluetooth_icon() {
    src="$ICONS/bluetooth_base_icon.svg"
    if [ -f "$src" ] && command -v blueman-manager >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/bluetooth.svg"
        echo "Bluetooth icon patched"
        patch_desktop_icon "bluetooth" "blueman-manager.desktop"
    fi
}

patch_btrfs_icon() {
    src="$ICONS/btrfs_base_icon.svg"
    if [ -f "$src" ] && command -v btrfs >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/btrfs.svg"
        echo "Btrfs icon patched"
        patch_desktop_icon "btrfs" "btrfs-assistant.desktop" "*btrfs*.desktop"
    fi
}

patch_cmake_icon() {
    src="$ICONS/cmake_base_icon.svg"
    if [ -f "$src" ] && command -v cmake >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/cmake.svg"
        echo "CMake icon patched"
        patch_desktop_icon "cmake" "cmake-gui.desktop" "*cmake*.desktop"
    fi
}

# Conky logomark
patch_conky_icon() {
    src="$ICONS/conky_base_icon.svg"
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

with open("$ICON_DIR/apps/scalable/conky.svg", "w") as f:
    f.write(svg)
print(f"Conky icon patched (dark={dark}, mid={mid}, light={light}, darker={darker})")
EOF

        patch_desktop_icon "conky" "conky.desktop" "*conky*.desktop"
    fi
}

# CoolerControl
patch_coolercontrol_icon() {
    src="$ICONS/coolercontrol_base_icon.svg"
    if [ -f "$src" ] && command -v coolercontrol >/dev/null 2>&1; then
        sed -e "s/#4d8cff/$accent/g" -e "s/#ff21ff/$accent/g" "$src" > "$ICON_DIR/apps/scalable/coolercontrol.svg"
        echo "CoolerControl icon patched"
        patch_desktop_icon "coolercontrol" "org.coolercontrol.CoolerControl.desktop" "*coolercontrol*.desktop"
    fi
}

patch_disks_utilities_icon() {
    src="$ICONS/disks_base_icon.svg"
    if [ -f "$src" ] && ( command -v gnome-disks >/dev/null 2>&1 || 
                          command -v gparted >/dev/null 2>&1 || 
                          command -v kdepartitionmanager >/dev/null 2>&1 || 
                          command -v kdiskmanager >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/disks.svg"
        echo "Disks utilities icon patched"
        patch_desktop_icon "disks" "org.gnome.DiskUtility.desktop"
        patch_desktop_icon "disks" "org.kde.filelight.desktop"
        patch_desktop_icon "disks" "gparted.desktop"
        patch_desktop_icon "disks" "org.kde.partitionmanager.desktop"
    fi
}

# Generic Electron placeholder — simple-icons logo (MIT), no fill attribute
# by default so inject one rather than sed-swapping a hex. Targets the
# versioned electronNN runtime packages (electron32, electron35, electron37,
# ...), which each ship their own generic "Electron NN" .desktop file —
# the numeric glob means new major versions get covered automatically,
# no need to touch this when Electron 38/39/etc. show up.
patch_electron_icon() {
    src="$ICONS/electron_base_icon.svg"
    if [ -f "$src" ]; then
        sed "s|viewBox=\"0 0 24 24\" xmlns|fill=\"$accent\" viewBox=\"0 0 24 24\" xmlns|" "$src" > "$ICON_DIR/apps/scalable/electron.svg"
        echo "Electron placeholder icon patched"
        patch_desktop_icon "electron" "electron[0-9]*.desktop"
        # Point any other unbranded Electron app at the same icon too:
        # patch_desktop_icon "electron" "some-electron-app.desktop"
    fi
}

# Fedora Media Writer — PNG-only icons, no scalable SVG upstream. Two-tone artwork: Fedora blue infinity mark + gray/white USB drive body. A plain ImageMagick -fuzz/-opaque match on the exact blue hex leaves anti-aliased edge pixels untouched (visible residual blue at small sizes); a fuzz wide enough to catch those starts eating into the gray drive body instead.
patch_fedora_media_writer_icon() {
    src="$ICONS/fedora_media_writer_base_icon.svg"
    if command -v mediawriter >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/fedora-media-writer.svg"
        echo "Fedora Media Writer icon patched"
        patch_desktop_icon "fedora-media-writer" "org.fedoraproject.MediaWriter.desktop"
    fi
}

# Image viewer icon
patch_image_viewer_icon() {
    src="$ICONS/image_viewer_base_icon.svg"
    if [ -f "$src" ] && ( command -v gwenview >/dev/null 2>&1 || 
                          command -v loupe >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/image_viewer.svg"
        echo "Gwenview icon patched"
        patch_desktop_icon "image_viewer" "gwenview.desktop" "*gwenview*.desktop"
        patch_desktop_icon "image_viewer" "org.gnome.Loupe.desktop" "*org.gnome.Loupe*.desktop"
    fi
}

# Hp icons
patch_hp_icon() {
    src="$ICONS/hp_base_icon.svg"
    if [ -f "$src" ] && command -v hp-toolbox >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/hp.svg"
        echo "HP icon patched"
        patch_desktop_icon "hp" "hp-uiscan.desktop"
        patch_desktop_icon "hp" "hplip.desktop"
    fi
}

# Text editor icon
patch_text_editor_icon() {
    src="$ICONS/text_editor_base_icon.svg"
    if [ -f "$src" ] && ( command -v kate >/dev/null 2>&1 || 
                          command -v kwrite >/dev/null 2>&1 || 
                          command -v micro >/dev/null 2>&1 || 
                          command -v gnome-text-editor >/dev/null 2>&1 || 
                          command -v xdvi >/dev/null 2>&1 ); then
        sed "s/gray/$accent/g" "$src" > "$ICON_DIR/apps/scalable/text_editor.svg"
        echo "Text editor icon patched"
        patch_desktop_icon "text_editor" "kate.desktop" "*kate*.desktop"
        patch_desktop_icon "text_editor" "kwrite.desktop" "*kwrite*.desktop"
        patch_desktop_icon "text_editor" "micro.desktop" "*micro*.desktop"
        patch_desktop_icon "text_editor" "org.gnome.TextEditor.desktop" "*org.gnome.TextEditor*.desktop"
        patch_desktop_icon "text_editor" "xdvi.desktop" "*xdvi*.desktop"
    fi
}

# Calculator icon
patch_calculator_icon() {
    src="$ICONS/calculator_base_icon.svg"
    if [ -f "$src" ] && ( command -v kcalc >/dev/null 2>&1 || 
                          command -v qalculate >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/calculator.svg"
        echo "Calculator icon patched"
        patch_desktop_icon "calculator" "kcalc.desktop" "*kcalc*.desktop"
        patch_desktop_icon "calculator" "qalculate-gtk.desktop"
    fi
}

# Brush icon
patch_brush_icon() {
    src="$ICONS/brush_base_icon.svg"
    if [ -f "$src" ] && (command -v kvantummanager >/dev/null 2>&1 || command -v nwg-look >/dev/null 2>&1); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/brush.svg"
        echo "Brush icon patched"
        patch_desktop_icon "brush" "kvantummanager.desktop"
        patch_desktop_icon "brush" "*nwg-look*.desktop"
    fi
}

# Lock icon
patch_lock_icon() {
    src="$ICONS/lock_base_icon.svg"
    if [ -f "$src" ] && command -v kwalletd6 >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/lock.svg"
        echo "Lock icon patched"
        patch_desktop_icon "lock" "*kwalletmanager*.desktop"
    fi
}

# Localsend icon
patch_localsend_icon() {
    src="$ICONS/localsend_base_icon.svg"
    if [ -f "$src" ] && command -v localsend >/dev/null 2>&1; then
        sed "s/#fff/$accent/g" "$src" > "$ICON_DIR/apps/scalable/localsend.svg"
        echo "Localsend icon patched"
        patch_desktop_icon "localsend" "localsend.desktop" "*localsend*.desktop"
    fi
}

# Printer icon
patch_printer_icon() {
    src="$ICONS/printer_base_icon.svg"
    if [ -f "$src" ] && [ -f /usr/share/applications/cups.desktop ]; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/printer.svg"
        echo "Printer icon patched"
        patch_desktop_icon "printer" "cups.desktop"
    fi
}

# Lychee icon
patch_lychee_icon() {
    src="$ICONS/lychee_base_icon.svg"
    if [ -f "$src" ] && command -v lycheeslicer >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/lychee.svg"
        echo "Lychee icon patched"
        patch_desktop_icon "lychee" "lychee.desktop" "*lychee*.desktop"
    fi
}

# Meld icon
patch_meld_icon() {
    src="$ICONS/meld_base_icon.svg"
    if [ -f "$src" ] && command -v meld >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/meld.svg"
        echo "Meld icon patched"
        patch_desktop_icon "meld" "meld.desktop" "*meld*.desktop"
    fi
}

# Neovim icon
patch_neovim_icon() {
    src="$ICONS/neovim_base_icon.svg"
    if [ -f "$src" ] && command -v nvim >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/neovim.svg"
        echo "Neovim icon patched"
        patch_desktop_icon "neovim" "nvim.desktop" "*nvim*.desktop"
    fi
}

# Nvidia X Server Settings icon
patch_nvidia_settings_icon() {
    src="$ICONS/nvidia_base_icon.svg"
    if [ -f "$src" ] && command -v nvidia-settings >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/nvidia.svg"
        echo "Nvidia X Server Settings icon patched"
        patch_desktop_icon "nvidia" "nvidia-settings.desktop"
    fi
}

# Install icon
patch_install_icon() {
    src="$ICONS/install_base_icon.svg"
    if [ -f "$src" ] && ( command -v octopi >/dev/null 2>&1 || 
                          command -v shelly >/dev/null 2>&1 ||
                          command -v cachyos-pi >/dev/null 2>&1); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/install.svg"
        echo "Install icon patched"
        patch_desktop_icon "install" "*octopi*.desktop"
        patch_desktop_icon "install" "*shelly*.desktop"
        patch_desktop_icon "install" "cachyos-pi.desktop" "*cachyos*pi*.desktop"
    fi
}

# Cloud storage icon
patch_cloud_storage_icon() {
    src="$ICONS/cloud_storage_base_icon.svg"
    if [ -f "$src" ] && command -v onedrive >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/cloud_storage.svg"
        echo "Cloud storage icon patched"
        patch_desktop_icon "cloud_storage" "*onedrive*.desktop"
    fi
}

# Code icon
patch_code_icon() {
    src="$ICONS/code_base_icon.svg"
    if [ -f "$src" ] && ( [ -d "/usr/lib/jvm" ] || command -v designer6 >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/code.svg"
        echo "Code icon patched"
        patch_desktop_icon "code" "*jdk*.desktop"
        patch_desktop_icon "code" "*designer*.desktop"
    fi
}

# Gaming icon
patch_gaming_icon() {
    src="$ICONS/gaming_base_icon.svg"
    if [ -f "$src" ] && ( command -v heroic >/dev/null 2>&1 || 
                          command -v lutris >/dev/null 2>&1 || 
                          command -v goverlay >/dev/null 2>&1 || 
                          command -v protonplus >/dev/null 2>&1 || 
                          command -v protontricks >/dev/null 2>&1 ); then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/gaming.svg"
        echo "Gaming icon patched"
        patch_desktop_icon "gaming" "lutris.desktop" "*lutris*.desktop"
        patch_desktop_icon "gaming" "heroic.desktop" "*heroic*.desktop"
        patch_desktop_icon "gaming" "goverlay.desktop" "*goverlay*.desktop"
        patch_desktop_icon "gaming" "protonplus.desktop" "*protonplus*.desktop"
        patch_desktop_icon "gaming" "protontricks.desktop" "*protontricks*.desktop"
    fi
}

# Launcher icon
patch_launcher_icon() {
    src="$ICONS/launcher_base_icon.svg"
    if [ -f "$src" ] && command -v rofi >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/launcher.svg"
        echo "Launcher icon patched"
        patch_desktop_icon "launcher" "rofi.desktop" "*rofi*.desktop"
    fi
}

# Logitech icon
patch_logitech_icon() {
    src="$ICONS/logitech_base_icon.svg"
    if [ -f "$src" ] && command -v solaar >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/logitech.svg"
        echo "Logitech icon patched"
        patch_desktop_icon "logitech" "solaar.desktop" "*solaar*.desktop"
    fi
}

# Screenshot icon
patch_screenshot_icon() {
    src="$ICONS/screenshot_base_icon.svg"
    if [ -f "$src" ] && command -v spectacle >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/screenshot.svg"
        echo "Screenshot icon patched"
        patch_desktop_icon "screenshot" "spectacle.desktop" "*spectacle*.desktop"
    fi
}

# Spotify icon
patch_spotify_icon() {
    src="$ICONS/spotify_base_icon.svg"
    if [ -f "$src" ] && command -v spotify >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/spotify.svg"
        echo "Spotify icon patched"
        patch_desktop_icon "spotify" "spotify.desktop" "*spotify*.desktop"
    fi
}

# Elgato icon
patch_elgato_icon() {
    src="$ICONS/elgato_base_icon.svg"
    if [ -f "$src" ] && command -v streamcontroller >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/elgato.svg"
        echo "Elgato icon patched"
        patch_desktop_icon "elgato" "streamcontroller.desktop" "*streamcontroller*.desktop"
    fi
}

# Vim icon
patch_vim_icon() {
    src="$ICONS/vim_base_icon.svg"
    if [ -f "$src" ] && command -v vim >/dev/null 2>&1; then
        sed "s/#000000/$accent/g" "$src" > "$ICON_DIR/apps/scalable/vim.svg"
        echo "Vim icon patched"
        patch_desktop_icon "vim" "vim.desktop" "*vim*.desktop"
    fi
}

# Volume icon
patch_volume_icon() {
    src="$ICONS/volume_base_icon.svg"
    if [ -f "$src" ] && command -v pavucontrol >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/volume.svg"
        echo "Volume icon patched"
        patch_desktop_icon "volume" "pavucontrol.desktop" "*pavucontrol*.desktop"
    fi
}

# Location icon
patch_location_icon() {
    src="$ICONS/location_base_icon.svg"
    if [ -f "$src" ] && command -v xgps >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/location.svg"
        echo "Location icon patched"
        patch_desktop_icon "location" "xgps.desktop" "*xgps*.desktop"
    fi
}

# Led icon
patch_led_icon() {
    src="$ICONS/led_base_icon.svg"
    if [ -f "$src" ] && command -v openrgb >/dev/null 2>&1; then
        sed "s/currentColor/$accent/g" "$src" > "$ICON_DIR/apps/scalable/led.svg"
        echo "LED icon patched"
        patch_desktop_icon "led" "openrgb.desktop" "*openrgb*.desktop"
    fi
}

# Wlogout icons
patch_wlogout_icons() {
    wlogout_icons_dir="$HOME/.config/wlogout/icons"
    if command -v wlogout >/dev/null 2>&1; then
        mkdir -p "$wlogout_icons_dir"

        # "Off"/standard state: same hue as accent, dimmed via reduced saturation + value, so it reads as "the same color, turned down" rather than an unrelated gray.
        standard=$(python3 -c "
import colorsys
h = '$accent'.lstrip('#')
r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
hh, s, v = colorsys.rgb_to_hsv(r, g, b)
nr, ng, nb = colorsys.hsv_to_rgb(hh, s * 0.5, v * 0.35)
print('#{:02x}{:02x}{:02x}'.format(int(nr*255), int(ng*255), int(nb*255)))
")

        # Hovered (full accent)
        sed "s/currentColor/$accent/g"   "$ICONS/lock_base_icon.svg"     > "$wlogout_icons_dir/lock-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/reboot_base_icon.svg"   > "$wlogout_icons_dir/reboot-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/power_base_icon.svg"    > "$wlogout_icons_dir/power-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/logout_base_icon.svg"   > "$wlogout_icons_dir/logout-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/sleep_base_icon.svg"    > "$wlogout_icons_dir/sleep-hovered.svg"
        sed "s/currentColor/$accent/g"   "$ICONS/suspend_base_icon.svg"  > "$wlogout_icons_dir/suspend-hovered.svg"

        # Standard (dimmed)
        sed "s/currentColor/$standard/g" "$ICONS/lock_base_icon.svg"     > "$wlogout_icons_dir/lock-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/reboot_base_icon.svg"   > "$wlogout_icons_dir/reboot-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/power_base_icon.svg"    > "$wlogout_icons_dir/power-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/logout_base_icon.svg"   > "$wlogout_icons_dir/logout-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/sleep_base_icon.svg"    > "$wlogout_icons_dir/sleep-standard.svg"
        sed "s/currentColor/$standard/g" "$ICONS/suspend_base_icon.svg"  > "$wlogout_icons_dir/suspend-standard.svg"

        echo "Wlogout icons patched (standard=$standard, hovered=$accent)"
    fi
}

# Swaync icons
patch_osd_icons() {
    local swaync_icons_dir="$HOME/.config/swaync/icons"
    local notif_red="#e74c3c"  # adjust to taste — not accent-derived, always red
    if command -v swaync >/dev/null 2>&1; then
        mkdir -p "$swaync_icons_dir"

        declare -A osd_icons=(
            [microphone]="microphone"
            [microphone-mute]="microphone-mute"
            [music]="music"
            [picture]="picture"
            [timer]="timer"
            [volume-high]="volume-high"
            [volume-mid]="volume-mid"
            [volume-low]="volume-low"
            [volume-mute]="volume-mute"
            [brightness-20]="brightness-20"
            [brightness-40]="brightness-40"
            [brightness-60]="brightness-60"
            [brightness-80]="brightness-80"
            [brightness-100]="brightness-100"
            [ok]="ok"
            [wallpaper_changer]="wallpaper_changer"
        )

        local patched=0
        for out_name in "${!osd_icons[@]}"; do
            src="$ICONS/${osd_icons[$out_name]}_base_icon.svg"
            if [ -f "$src" ]; then
                sed -e "s/currentColor/$accent/g" "$src" > "$swaync_icons_dir/${out_name}.svg"
                patched=$((patched + 1))
            fi
        done

        # Error/note icons: always red, independent of the accent color
        for out_name in error note; do
            src="$ICONS/${out_name}_base_icon.svg"
            if [ -f "$src" ]; then
                sed "s/currentColor/$notif_red/g" "$src" > "$swaync_icons_dir/${out_name}.svg"
                patched=$((patched + 1))
            fi
        done

        if [ "$patched" -gt 0 ]; then
            echo "OSD icons patched ($patched/16)"
        else
            echo "  no OSD base icons found to patch"
        fi
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
patch_cachyos_kernel_manager_icon
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
patch_system_monitor_icon
patch_onlyoffice_icon
patch_obs_studio_icon
patch_davinci_resolve_icon
patch_kde_connect_icon
patch_nwg_displays_icon
patch_vial_icon
patch_network_icons
patch_arduino_ide_icon
patch_ark_icon
patch_player_icon
patch_blackmagic_raw_speedtest_icon
patch_generic_settings_icon
patch_blender_icon
patch_bluetooth_icon
patch_btrfs_icon
patch_cmake_icon
patch_conky_icon
patch_coolercontrol_icon
patch_disks_utilities_icon
patch_electron_icon
patch_fedora_media_writer_icon
patch_image_viewer_icon
patch_hp_icon
patch_text_editor_icon
patch_calculator_icon
patch_brush_icon
patch_lock_icon
patch_localsend_icon
patch_printer_icon
patch_lychee_icon
patch_meld_icon
patch_neovim_icon
patch_nvidia_settings_icon
patch_install_icon
patch_cloud_storage_icon
patch_code_icon
patch_gaming_icon
patch_launcher_icon
patch_logitech_icon
patch_screenshot_icon
patch_spotify_icon
patch_elgato_icon
patch_vim_icon
patch_volume_icon
patch_location_icon
patch_led_icon
patch_wlogout_icons
patch_osd_icons

cleanup_icon_cache

echo "Icons patched with $accent"