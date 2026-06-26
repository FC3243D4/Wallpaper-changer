#!/usr/bin/env bash

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

# --- KDE accent color theming ---
R=$((16#${color:0:2}))
G=$((16#${color:2:2}))
B=$((16#${color:4:2}))
accent="#${color,,}"

# 1. Patch BreezeDark.colors (used by KColorScheme/Breeze style)
BREEZE_COLORS="$HOME/.local/share/color-schemes/BreezeDark.colors"
if [ -f "$BREEZE_COLORS" ]; then
    sed -i "s/^DecorationFocus=.*/DecorationFocus=$R,$G,$B/" "$BREEZE_COLORS"
    sed -i "s/^DecorationHover=.*/DecorationHover=$R,$G,$B/" "$BREEZE_COLORS"
    # Better approach for ForegroundActive - use awk to only patch Colors:View section
    awk -v rgb="$R,$G,$B" '
        /^\[Colors:View\]/ { in_view=1 }
        /^\[/ && !/^\[Colors:View\]/ { in_view=0 }
        in_view && /^ForegroundActive=/ { print "ForegroundActive=" rgb; next }
        { print }
    ' "$BREEZE_COLORS" > /tmp/BreezeDark.colors && mv /tmp/BreezeDark.colors "$BREEZE_COLORS"
fi

# 2. Patch qt6ct palette (used by qt6ct-style)
QT6CT_CONF="$HOME/.config/qt6ct/colors/BreezeDark.conf"
if [ -f "$QT6CT_CONF" ]; then
    # Replace whatever the current highlight color is (index 13 in the palette)
    sed -i "s/#ff[0-9a-fA-F]\{6\}, #fffcfcfc, #ff2980b9/#ff${color,,}, #fffcfcfc, #ff2980b9/g" "$QT6CT_CONF"
fi

# 3. Patch kdeglobals directly
kwriteconfig6 --file kdeglobals --group "Colors:View" --key "DecorationFocus" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View" --key "DecorationHover" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "Colors:View" --key "ForegroundActive" "$R,$G,$B"
kwriteconfig6 --file kdeglobals --group "General" --key "AccentColor" "$R,$G,$B"

# 4. Patch icon SVGs in breeze-dark-accent override theme
ICON_DIR="$HOME/.local/share/icons/breeze-dark-accent"

# Ensure all sizes use the colored SVG (16/24 were monochrome originally)
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

# 5. Restart Dolphin to pick up new icons
pkill dolphin && sleep 0.5 && dolphin &

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

#Restart waybar and kill kded6 to ensure functiin of tray module
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
