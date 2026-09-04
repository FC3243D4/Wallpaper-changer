#!/usr/bin/env bash
# WallpaperRandomAuto.sh (Wayland)
# Applies a random wallpaper on a fixed interval.
# Usage: WallpaperRandomAuto.sh [sfw|nsfw]

interval=1800   # seconds between switches (30 minutes)

while true; do
    if ! [ -z "$1" ]; then
        if [ "$1" == "nsfw" ]; then
            $HOME/.config/WallpaperChanger/WallpaperApplicator.sh random nsfw
        elif [ "$1" == "sfw" ]; then
            $HOME/.config/WallpaperChanger/WallpaperApplicator.sh random sfw
        else
            $HOME/.config/WallpaperChanger/WallpaperApplicator.sh random
        fi
    fi
    sleep $interval
done