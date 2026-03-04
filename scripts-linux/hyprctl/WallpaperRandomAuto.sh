#!/usr/bin/env bash

#$1 nsfw or sfw flag

# This controls (in seconds) when to switch to the next image
INTERVAL=1800 #30 minutes

while true; do
    if ! [ -z "$1" ]; then
        if [ "$1" == "nsfw" ]; then
            $HOME/.config/WallpaperChanger/WallpaperRandomSelect.sh nsfw
        elif [ "$1" == "sfw" ]; then
            $HOME/.config/WallpaperChanger/WallpaperRandomSelect.sh sfw
        else
            $HOME/.config/WallpaperChanger/WallpaperRandomSelect.sh
        fi
    fi
    sleep $INTERVAL
done