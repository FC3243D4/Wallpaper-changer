#!/usr/bin/env bash
#Script for random wallpaper on all displays based on their aspect ratio

primary=$(xrandr | grep primary)
primary=${primary%%[[:space:]]*}

#get resolution of display
width=$(cut -d 'x' -f1 <<< $2)
height=$(cut -d 'x' -f2 <<< $2)
echo "Width: $width Height: $height"

#call aspect ratio checker script
Wallpaper=$($HOME/.config/WallpaperChanger/AspectRatioChecker.sh $width $height)

#get full path of wallpaper based on aspect ratio folder and wallpaper name
Wallpaper+=$3

# Transition config
FPS=144
TYPE="any"
DURATION=1
BEZIER=".43,1.19,1,.4"
AWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

#transition wallpaper on display
awww query || awww-daemon --format xrgb && awww img -o $1 $Wallpaper $AWWW_PARAMS

if [[ $primary == $1 ]]
    then
        ln -sf $Wallpaper $HOME/.config/WallpaperChanger/.current_wallpaper
    fi
