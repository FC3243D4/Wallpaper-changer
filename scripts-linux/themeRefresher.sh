#!/usr/bin/env bash

# Save Hyprland layout state before any restarts
"$HOME/.config/WallpaperChanger/hyprMasterLayoutPreservation.sh" save

#Get dominant color from wallpaper
colorLine="$($HOME/.config/WallpaperChanger/dominantcolor -m 1 -n 2 -e black -p dominant $HOME/.config/WallpaperChanger/.current_wallpaper | grep -E '#')"
color=$(echo $colorLine | tr -d '#')
echo "Dominant color: #$color"

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

#refresh color pallette
wallust run -s $HOME/.config/WallpaperChanger/.current_wallpaper

# --- KDE & GTK accent color theming ---
R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))
accent="#${color,,}"

# Ensure colors.css exists to avoid GTK warnings
touch "$HOME/.config/gtk-3.0/colors.css"
touch "$HOME/.config/gtk-4.0/colors.css"

# 1. Patch BreezeDark.colors (used by KColorScheme/Breeze style)
BREEZE_COLORS="$HOME/.local/share/color-schemes/BreezeDark.colors"
if [ -f "$BREEZE_COLORS" ]; then
    sed -i "s/^DecorationFocus=.*/DecorationFocus=$R,$G,$B/" "$BREEZE_COLORS"
    sed -i "s/^DecorationHover=.*/DecorationHover=$R,$G,$B/" "$BREEZE_COLORS"
    # Only patch ForegroundActive in [Colors:View], not globally
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:View\]/ { in_view=1 }
        /^\[/ && !/^\[Colors:View\]/ { in_view=0 }
        in_view && /^ForegroundActive=/ { print "ForegroundActive=" rgb; next }
        { print }
    ' "$BREEZE_COLORS" > /tmp/BreezeDark.colors && mv /tmp/BreezeDark.colors "$BREEZE_COLORS"
    # Only patch BackgroundNormal in [Colors:Selection]
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:Selection\]/ { in_sel=1 }
        /^\[/ && !/^\[Colors:Selection\]/ { in_sel=0 }
        in_sel && /^BackgroundNormal=/ { print "BackgroundNormal=" rgb; next }
        { print }
    ' "$BREEZE_COLORS" > /tmp/BreezeDark.colors && mv /tmp/BreezeDark.colors "$BREEZE_COLORS"
fi

# 2. Patch qt6ct palette (used by qt6ct-style)
QT6CT_CONF="$HOME/.config/qt6ct/colors/BreezeDark.conf"
if [ -f "$QT6CT_CONF" ]; then
    sed -i "s/#ff[0-9a-fA-F]\{6\}, #fffcfcfc, #ff2980b9/#ff${color,,}, #fffcfcfc, #ff2980b9/g" "$QT6CT_CONF"
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

# 3b. Patch Breeze-Dark GTK theme user copy
GTK_BASE="$HOME/.local/share/themes/Breeze-Dark"
if [ -d "$GTK_BASE" ]; then
    for css in "$GTK_BASE/gtk-3.0/gtk.css" "$GTK_BASE/gtk-4.0/gtk.css"; do
        if [ -f "$css" ]; then
            current=$(grep "theme_selected_bg_color_breeze #" "$css" | grep -oP '#[0-9a-fA-F]{6}' | head -1)
            if [ -n "$current" ]; then
                cr=$((16#${current:1:2}))
                cg=$((16#${current:3:2}))
                cb=$((16#${current:5:2}))
                sed -i "s/${current}/#${color,,}/g" "$css"
                sed -i "s/rgba($cr, $cg, $cb,/rgba($R, $G, $B,/g" "$css"
            fi
        fi
    done
fi

# 3c. Patch gtk.css treeview selection color
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

# 4. Patch icon SVGs in breeze-dark-accent override theme
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"

cp "$ICON_DIR/places/48/folder.svg" "$ICON_DIR/places/16/folder.svg"
cp "$ICON_DIR/places/48/folder.svg" "$ICON_DIR/places/24/folder.svg"

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
    [ -f "$svg" ] && sed -i "s/color: #[0-9a-fA-F]\{6\}/color: $accent/g" "$svg"
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