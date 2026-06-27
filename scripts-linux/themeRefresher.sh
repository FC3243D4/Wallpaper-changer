#!/usr/bin/env bash

# Save Hyprland layout state before any restarts
"$HOME/.config/WallpaperChanger/hyprMasterLayoutPreservation.sh" save

WALLPAPER="$HOME/.config/WallpaperChanger/.current_wallpaper"
BRIGHTNESS_THRESHOLD=40
color=""

# Try matugen candidates 0-4 in order
for i in 0 1 2 3 4; do
    matugen image "$WALLPAPER" --source-color-index $i --quiet

    candidate=$(cat ~/.cache/matugen/source-color | tr -d '[:space:]')
    R=$((16#${candidate:0:2}))
    G=$((16#${candidate:2:2}))
    B=$((16#${candidate:4:2}))
    brightness=$(( (R * 299 + G * 587 + B * 114) / 1000 ))
    echo "Candidate $i: #$candidate (brightness: $brightness)"

    if [ "$brightness" -ge "$BRIGHTNESS_THRESHOLD" ]; then
        color="$candidate"
        echo "Using candidate $i: #$color"
        break
    fi
done

# If all candidates were too dark, fall back to dominantcolor
if [ -z "$color" ]; then
    echo "All matugen candidates too dark, falling back to dominantcolor..."
    colorLine="$($HOME/.config/WallpaperChanger/dominantcolor -m 1 -n 2 -e black -p dominant "$WALLPAPER" | grep -E '#')"
    color=$(echo $colorLine | tr -d '#')
    matugen color hex "#$color" --quiet
fi

colorLine="#$color"
R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))
accent="#${color,,}"
echo "Final color: #$color"

# Validate color before proceeding
if [ ${#color} -ne 6 ] || ! echo "$color" | grep -qE '^[0-9a-fA-F]{6}$'; then
    echo "ERROR: Invalid color '$color', aborting theme refresh"
    exit 1
fi

#apply color to openrgb
if ! openrgb --version &> /dev/null; then
    echo "OpenRGB is not installed. Skipping color application."
else
    echo "OpenRGB detected. Applying dominant color to OpenRGB devices..."
    openrgb -c $color
fi

#apply color to logitech G devices
devices=($(ratbagctl list | grep -oP '^[\w-]+(?=:)'))

for device in "${devices[@]}"; do
  profiles=($(ratbagctl "$device" info | grep -oP '^Profile \K\d+'))
  for profile in "${profiles[@]}"; do
    ratbagctl "$device" profile $profile led 0 set mode on color $color
  done
done

# Ensure colors.css exists to avoid GTK warnings
touch "$HOME/.config/gtk-3.0/colors.css"
touch "$HOME/.config/gtk-4.0/colors.css"

# 1. Patch BreezeDark.colors (always from clean base)
BREEZE_COLORS="$HOME/.local/share/color-schemes/BreezeDark.colors"
BREEZE_COLORS_BASE="$HOME/.local/share/color-schemes/BreezeDark.colors.base"

if [ ! -f "$BREEZE_COLORS_BASE" ] && [ -f "$BREEZE_COLORS" ]; then
    cp "$BREEZE_COLORS" "$BREEZE_COLORS_BASE"
fi

if [ -f "$BREEZE_COLORS_BASE" ]; then
    cp "$BREEZE_COLORS_BASE" "$BREEZE_COLORS"
    sed -i "s/^DecorationFocus=.*/DecorationFocus=$R,$G,$B/" "$BREEZE_COLORS"
    sed -i "s/^DecorationHover=.*/DecorationHover=$R,$G,$B/" "$BREEZE_COLORS"
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:View\]/ { in_view=1 }
        /^\[/ && !/^\[Colors:View\]/ { in_view=0 }
        in_view && /^ForegroundActive=/ { print "ForegroundActive=" rgb; next }
        { print }
    ' "$BREEZE_COLORS" > /tmp/BreezeDark.colors && mv /tmp/BreezeDark.colors "$BREEZE_COLORS"
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:Selection\]/ { in_sel=1 }
        /^\[/ && !/^\[Colors:Selection\]/ { in_sel=0 }
        in_sel && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$BREEZE_COLORS" > /tmp/BreezeDark.colors && mv /tmp/BreezeDark.colors "$BREEZE_COLORS"
fi

# 2. Patch qt6ct palette (always from clean base)
QT6CT_CONF="$HOME/.config/qt6ct/colors/BreezeDark.conf"
QT6CT_BASE="$HOME/.config/qt6ct/colors/BreezeDark.conf.base"

if [ ! -f "$QT6CT_BASE" ] && [ -f "$QT6CT_CONF" ]; then
    cp "$QT6CT_CONF" "$QT6CT_BASE"
fi

if [ -f "$QT6CT_BASE" ]; then
    cp "$QT6CT_BASE" "$QT6CT_CONF"
    sed -i "s/#ff3daee9/#ff${color,,}/g" "$QT6CT_CONF"
fi

# 3. Patch kdeglobals directly
kwriteconfig6 --file kdeglobals --group "Colors:View" --key "DecorationFocus" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View" --key "DecorationHover" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View" --key "ForegroundActive" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundNormal" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:Selection" --key "BackgroundAlternate" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "General" --key "AccentColor" "$R,$G,$B"

# Signal KDE apps to reload colors live
qdbus6 org.kde.KGlobalSettings /KGlobalSettings notifyChange 0 0 2>/dev/null || true

# 3b. Patch Breeze-Dark GTK theme (always from system copy)
GTK_BASE="$HOME/.local/share/themes/Breeze-Dark"
if [ -d "$GTK_BASE" ]; then
    for gtk_ver in gtk-3.0 gtk-4.0; do
        sys_css="/usr/share/themes/Breeze-Dark/$gtk_ver/gtk.css"
        usr_css="$GTK_BASE/$gtk_ver/gtk.css"
        if [ -f "$sys_css" ]; then
            cp "$sys_css" "$usr_css"
            sed -i "s/theme_view_hover_decoration_color_breeze #[0-9a-fA-F]*/theme_view_hover_decoration_color_breeze #${color,,}/g" "$usr_css"
            sed -i "s/theme_hovering_selected_bg_color_breeze #[0-9a-fA-F]*/theme_hovering_selected_bg_color_breeze #${color,,}/g" "$usr_css"
            sed -i "s/theme_selected_bg_color_breeze #[0-9a-fA-F]*/theme_selected_bg_color_breeze #${color,,}/g" "$usr_css"
            sed -i "s/theme_view_active_decoration_color_breeze #[0-9a-fA-F]*/theme_view_active_decoration_color_breeze #${color,,}/g" "$usr_css"
            sed -i "s/theme_unfocused_selected_bg_color_alt_breeze #[0-9a-fA-F]*/theme_unfocused_selected_bg_color_alt_breeze #${color,,}/g" "$usr_css"
            sed -i "s/theme_button_decoration_hover_breeze  #[0-9a-fA-F]*/theme_button_decoration_hover_breeze  #${color,,}/g" "$usr_css"
            sed -i "s/theme_button_decoration_focus_breeze  #[0-9a-fA-F]*/theme_button_decoration_focus_breeze  #${color,,}/g" "$usr_css"
            sed -i "s/theme_button_decoration_hover_backdrop_breeze  #[0-9a-fA-F]*/theme_button_decoration_hover_backdrop_breeze  #${color,,}/g" "$usr_css"
            sed -i "s/theme_button_decoration_focus_backdrop_breeze  #[0-9a-fA-F]*/theme_button_decoration_focus_backdrop_breeze  #${color,,}/g" "$usr_css"
            sed -i "s/rgba([0-9]*, [0-9]*, [0-9]*,/rgba($R, $G, $B,/g" "$usr_css"
        fi
    done
fi

# 3c. Patch gtk.css treeview selection color (always fully overwritten)
cat > "$HOME/.config/gtk-3.0/gtk.css" << EOF
treeview {
    background-color: #202326;
    color: #eff0f1;
}
treeview:selected {
    background-color: #${color,,};
}
treeview header button {
    background-color: #202326;
    color: #eff0f1;
    border-color: #2d3036;
}
.sidebar {
    background-color: #202326;
    color: #eff0f1;
}
.sidebar row:selected {
    background-color: #${color,,};
}
EOF

# Nudge GTK apps to reload theme live
current_theme=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
gsettings set org.gnome.desktop.interface gtk-theme ''
sleep 0.1
gsettings set org.gnome.desktop.interface gtk-theme "$current_theme"

# Clear GTK cache and restart portal
rm -rf "$HOME/.cache/gtk-3.0" "$HOME/.cache/gtk-4.0"
systemctl --user restart xdg-desktop-portal-gtk
systemctl --user restart xdg-desktop-portal

# 4. Patch icon SVGs (always from system breeze-dark to avoid double-patching)
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"

for size in 16 22 24 32 48 64 96; do
    src="/usr/share/icons/breeze-dark/places/$size/folder.svg"
    [ -f "$src" ] && cp "$src" "$ICON_DIR/places/$size/folder.svg"
done
cp /usr/share/icons/breeze-dark/mimetypes/64/inode-directory.svg \
   "$ICON_DIR/mimetypes/64/inode-directory.svg" 2>/dev/null

for svg in \
    "$ICON_DIR/places/16/folder.svg" \
    "$ICON_DIR/places/22/folder.svg" \
    "$ICON_DIR/places/24/folder.svg" \
    "$ICON_DIR/places/32/folder.svg" \
    "$ICON_DIR/places/48/folder.svg" \
    "$ICON_DIR/places/64/folder.svg" \
    "$ICON_DIR/places/96/folder.svg" \
    "$ICON_DIR/mimetypes/64/inode-directory.svg"
do
    [ -f "$svg" ] && sed -i "s/ColorScheme-Accent { color: #[0-9a-fA-F]*/ColorScheme-Accent { color: $accent/g" "$svg"
done

# 5. Patch VS Code color customizations
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
if [ -f "$VSCODE_SETTINGS" ]; then
    python3 << EOF
import json
with open('$VSCODE_SETTINGS', 'r') as f:
    settings = json.load(f)
settings['workbench.colorCustomizations'] = {
    "list.activeSelectionBackground": "#${color,,}99",
    "list.hoverBackground": "#${color,,}33",
    "list.focusBackground": "#${color,,}99",
    "menu.selectionBackground": "#00000000",
    "menu.selectionBorder": "#${color,,}",
    "menu.border": "#${color,,}33",
    "quickInputList.focusBackground": "#${color,,}99",
    "focusBorder": "#${color,,}",
    "activityBar.activeBorder": "#${color,,}",
    "tab.activeBorderTop": "#${color,,}",
    "editorCursor.foreground": "#${color,,}",
    "selection.background": "#${color,,}55"
}
with open('$VSCODE_SETTINGS', 'w') as f:
    json.dump(settings, f, indent=4)
print('VS Code colors updated')
EOF
fi

# 6. Patch Zen Browser chrome with accent color
for ZEN_PROFILE in "$HOME/.zen/8ma66p8a.Default (release)" "$HOME/.zen/k71gdxvw.Default Profile"; do
    if [ -d "$ZEN_PROFILE" ]; then
        mkdir -p "$ZEN_PROFILE/chrome"
        cat > "$ZEN_PROFILE/chrome/userChrome.css" << EOF
/* Generated by themeRefresher */
:root {
    --lwt-accent-color: #${color,,} !important;
    --toolbar-field-focus-border-color: #${color,,} !important;
    --toolbar-field-color: #fcfcfc !important;
    --toolbar-field-focus-color: #fcfcfc !important;
    --toolbar-color: #fcfcfc !important;
    --urlbar-box-text-color: #fcfcfc !important;
}

#urlbar-input {
    color: #fcfcfc !important;
}

::selection {
    background-color: #${color,,} !important;
    color: #ffffff !important;
}
EOF
        cat > "$ZEN_PROFILE/chrome/userContent.css" << EOF
/* Generated by themeRefresher */
::selection {
    background-color: #${color,,} !important;
    color: #ffffff !important;
}
EOF
        if ! grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$ZEN_PROFILE/prefs.js" 2>/dev/null; then
            echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$ZEN_PROFILE/prefs.js"
        fi
    fi
done

# 7. Restart Dolphin to pick up new icons
pkill dolphin && sleep 0.5 && dolphin &

# 8. Restart Zen
if pgrep -f zen-bin > /dev/null; then
    pkill -f zen-bin
    sleep 1
    zen-browser &
fi

# 9. Restart Ferdium
FERDIUM_SETTINGS=~/.config/Ferdium/config/settings.json
if [ -f "$FERDIUM_SETTINGS" ]; then
    jq --arg color "$colorLine" \
        '.accentColor = $color | .progressbarAccentColor = $color' \
        "$FERDIUM_SETTINGS" > /tmp/ferdium-settings.tmp \
        && mv /tmp/ferdium-settings.tmp "$FERDIUM_SETTINGS"

    if pgrep -f "electron.*ferdium-bin" > /dev/null; then
        pkill -f "electron.*ferdium-bin"
        sleep 1
        ferdium >/dev/null 2>&1 &disown
    fi
fi

# Kill already running processes
_ps=(rofi swaync ags)
for _prs in "${_ps[@]}"; do
  if pidof "${_prs}" >/dev/null; then
    pkill "${_prs}"
  fi
done

# quit quickshell & relaunch quickshell
pkill qs && qs &

# some process to kill
for pid in $(pidof rofi swaync ags swaybg); do
  kill -SIGUSR1 "$pid"
  sleep 0.1
done

#Restart waybar and kill kded6 to ensure function of tray module
if [ $XDG_SESSION_DESKTOP == "Hyprland" ]; then
    killall waybar
    sleep 0.5
    waybar &

    # relaunch swaync
    sleep 0.3
    swaync >/dev/null 2>&1 &
    # reload swaync
    swaync-client --reload-config

    sleep 2
    echo "killing kded6 to refresh system tray"
    pkill "kded6"
else
    echo "Not running Hyprland, skipping waybar restart."
fi

#reload kitty
kill -SIGUSR1 $(pidof kitty)

# Restore Hyprland layout state after all restarts
"$HOME/.config/WallpaperChanger/hyprMasterLayoutPreservation.sh" restore