#!/usr/bin/env bash

# This controls (in seconds) when to switch to the next image
INTERVAL=1800 #30 minutes

while true; do
    $HOME/.config/WallpaperChanger/WallpaperRandomSelectXrandrNSFW.sh
    sleep $INTERVAL
done