#!/usr/bin/env bash

SCRIPTSDIR="$HOME/.config/hypr/scripts"

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

#refresh color pallette
wallust run -s $HOME/.config/WallpaperChanger/.current_wallpaper

#refresh hyprland
sleep 2
$SCRIPTSDIR/Refresh.sh

#reload kitty
kill -SIGUSR1 $(pidof kitty)