#!/usr/bin/env bash

SCRIPTSDIR="$HOME/.config/hypr/scripts"

#Get connected displays and maps them to an array
displays=$(hyprctl monitors | awk '/Monitor/{print}')
mapfile -t -O 1 var < <(echo "$displays")

resolutions=$(hyprctl monitors | awk '/Monitor/{getline; print}')
mapfile -t -O 1 res < <(echo "$resolutions")

n=1
while [[ -n ${var[$n]} ]]; do
    screen=${var[$n]}
    screen=$(echo $screen | tr -d ' ')
    screen=$(cut -d '(' -f1 <<< $screen)
    screen=$(cut -d 'r' -f2 <<< $screen)

    resolution=${res[$n]}
    resolution=$(echo $resolution | tr -d ' ')
    resolution=$(cut -d '@' -f1 <<< $resolution)
    
    echo "Changing wallpapers on display: $screen"
    echo "with resolution: $resolution"
    $HOME/.config/WallpaperChanger/WallpaperApplicator.sh $screen $resolution $1 && echo "done"
    ((n++))
done

#refresh color pallette
wallust run -s $HOME/.config/WallpaperChanger/.current_wallpaper

#refresh hyprland
sleep 2
$SCRIPTSDIR/Refresh.sh

#reload kitty
kill -SIGUSR1 $(pidof kitty)

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


