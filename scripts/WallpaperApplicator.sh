#!/usr/bin/env bash
#Script for random wallpaper on all displays based on their aspect ratio

primary=$(xrandr | grep primary)
primary=${primary%%[[:space:]]*}

echo ""
echo "Primary display: $primary"
echo ""
echo "$1"
echo ""

#get resolution of display
width=$(cut -d 'x' -f1 <<< $2)
height=$(cut -d 'x' -f2 <<< $2)
echo "Width: $width Height: $height"

#call aspect ratio checker script
$HOME/.config/hypr/UserScripts/AspectRatioChecker.sh $width $height

#check if aspect ratio matched any known ratios if not set default folder
if [ ! -f $HOME/.config/hypr/UserScripts/aspectRatio.tmp ]; then
    Wallpaper="$HOME/Pictures/wallpapers/32-9"
else
    Wallpaper=$(cat $HOME/.config/hypr/UserScripts/aspectRatio.tmp)
    rm $HOME/.config/hypr/UserScripts/aspectRatio.tmp
fi

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
        echo "Primary display, wallpaper: $Wallpaper"
        ln -sf $Wallpaper $HOME/.config/rofi/.current_wallpaper
    fi
