#!/usr/bin/env bash
# WallpaperRandomAutoXrandr.sh (Xrandr, for non-Wayland users)
# Applies a random wallpaper on a fixed interval.
# Usage: WallpaperRandomAutoXrandr.sh [sfw|nsfw]

interval=1800   # seconds between switches (30 minutes)

while true; do
    if ! [ -z "$1" ]; then
        if [ "$1" == "nsfw" ]; then
            $HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random nsfw
        elif [ "$1" == "sfw" ]; then
            $HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random sfw
        else
            $HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random
        fi
    fi
    sleep $interval
done