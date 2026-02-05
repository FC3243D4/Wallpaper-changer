#!/usr/bin/env bash

wallDIR="$HOME/Pictures/wallpapers/16-9"
#select random wallpaper
PICS=($(find -L ${wallDIR} -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.pnm" -o -name "*.tga" -o -name "*.tiff" -o -name "*.webp" -o -name "*.bmp" -o -name "*.farbfeld" -o -name "*.gif" \)))


#get current wallpaper to avoid repetition
Wallpaper=$(readlink -f /home/fc3243d4/.config/rofi/.current_wallpaper)
RANDOMPICS=$Wallpaper

wallpaper_path=${RANDOMPICS#*$HOME/Pictures/wallpapers/}
wallpaper_path=$(echo "$wallpaper_path" | sed 's,^[^/]*/,,')
wallpaper_path="/$wallpaper_path"

RANDOMPICS=$wallpaper_path



#chooses new image until it is different from current one
while [ "$RANDOMPICS" == "$wallpaper_path" ]
do
    RANDOMPICS=${PICS[ $RANDOM % ${#PICS[@]} ]}
    RANDOMPICS=${RANDOMPICS#*$HOME/Pictures/wallpapers/}
    RANDOMPICS=$(echo "$RANDOMPICS" | sed 's,^[^/]*/,,')
    RANDOMPICS="/$RANDOMPICS"
done

$HOME/.config/hypr/UserScripts/WallpaperAspectRatio.sh $RANDOMPICS