#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Script for Random Wallpaper ( CTRL ALT W)

#get resolution of primary display
xrandr | grep -w connected  | awk -F'[ +]' '{print $1,$3,$4}' > aspectRatio.tmp
info="$(grep -E 'primary' aspectRatio.tmp)"
resolution=${info#*y}
width=${resolution%x*}
height=${resolution#*x}

#get aspect ratio multiplied by 1000 to check for decimal
value100="$((9000 * width/height))"
dec=${value100: -3}

#check if asect ratio is x:9
if [ "$dec" = "000" ]; then

    #get height in aspect ratio
    ratio="$((9 * width/height))"

    #check if aspect ratio is 32:9
    if [ "$ratio" = "32" ]; then
        wallDIR="$HOME/Pictures/wallpapers/32-9"

    #check if aspect ratio is 16:9
    elif [ "$ratio" = "16" ]; then
            wallDIR="$HOME/Pictures/wallpapers/16-9"
    fi

#aspect ratio is x:10
else
    ratio="$((10 * width/height))"
    wallDIR="$HOME/Pictures/wallpapers/16-10"
fi

#wallDIR="$HOME/Pictures/wallpapers/32-9"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
Wallpaper= readlink -f /home/fc3243d4/.config/rofi/.current_wallpaper
RANDOMPICS=$Wallpaper

focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')

PICS=($(find -L ${wallDIR} -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.pnm" -o -name "*.tga" -o -name "*.tiff" -o -name "*.webp" -o -name "*.bmp" -o -name "*.farbfeld" -o -name "*.gif" \)))

#chooses new image until it is different from current one
while [$RANDOMPICS == $Wallpaper]
do
    RANDOMPICS=${PICS[ $RANDOM % ${#PICS[@]} ]}
done

# Transition config
FPS=60
TYPE="any"
DURATION=1
BEZIER=".43,1.19,1,.4"
AWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

awww query || awww-daemon --format xrgb && awww img -o $focused_monitor ${RANDOMPICS} $AWWW_PARAMS

ln -sf $RANDOMPICS $HOME/.config/rofi/.current_wallpaper

wallust run -s "$RANDOMPICS"

sleep 2
$SCRIPTSDIR/Refresh.sh

#reload kitty
kill -SIGUSR1 $(pidof kitty)

#Get dominant color from wallpaper
$HOME/dominantcolor -n 2 -e black -p dominant $HOME/.config/rofi/.current_wallpaper > color.tmp
colorLine="$(grep -E '#' color.tmp)"
color=$(echo $colorLine | tr -d '#')

echo "Dominant color: $color"

#apply color to openrgb
openrgb -c $color

#remove temp file
rm color.tmp
