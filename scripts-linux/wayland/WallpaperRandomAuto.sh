#!/usr/bin/env bash

#$1 nsfw or sfw flag

# This controls (in seconds) when to switch to the next image
INTERVAL=1800 #30 minutes

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
    sleep $INTERVAL
done