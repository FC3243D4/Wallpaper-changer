#!/usr/bin/env bash

SCRIPTSDIR="$HOME/.config/hypr/scripts"

#xrandr version
#Get connected displays and maps them to an array
xrandr | grep " connected " | awk '{ print$1 }' > display_list.tmp
mapfile -t -O 1 var < display_list.tmp
rm display_list.tmp

Risoluzioni=$(xrandr --current | grep '*' | uniq | awk '{print $1}')
mapfile -t -O 1 res < <(echo "$Risoluzioni")

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
    $HOME/.config/hypr/UserScripts/WallpaperApplicator.sh $screen $resolution $1 && echo "done"
    ((n++))
done

#refresh color pallette
wallust run -s $HOME/.config/rofi/.current_wallpaper

#refresh hyprland
sleep 2
$SCRIPTSDIR/Refresh.sh

#reload kitty
kill -SIGUSR1 $(pidof kitty)

#Get dominant color from wallpaper
colorLine="$($HOME/.config/hypr/UserScripts/dominantcolor -m 1 -n 2 -e black -p dominant $HOME/.config/rofi/.current_wallpaper | grep -E '#')"
color=$(echo $colorLine | tr -d '#')
echo "Dominant color: #$color"

#apply color to openrgb
openrgb -c $color



