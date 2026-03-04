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
    $HOME/.config/WallpaperChanger/WallpaperApplicator.sh $screen $resolution $1 && echo "done"
    ((n++))
done

#refresh theme
$HOME/.config/WallpaperChanger/themeRefresher.sh



