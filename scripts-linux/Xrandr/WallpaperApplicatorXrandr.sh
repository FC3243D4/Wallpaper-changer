#!/usr/bin/env bash

# $1 = if file use it, if random selects random wallpaper from the directory
# $2 = sfw or nsfw

#get primary display to set the current wallpaper symlink to the correct one
primary=$(xrandr | grep primary)
primary=${primary%%[[:space:]]*}

echo "Running WallpaperRandomSelect.sh with arguments: $1 $2"

wallBaseDIR="$HOME/Pictures/wallpapers"
if [ -d "$wallBaseDIR/16-9" ]; then
    wallDIR="$wallBaseDIR/16-9"
else
    wallDIR=$(find "$wallBaseDIR" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)
    if [ -z "$wallDIR" ]; then
        echo "No '16-9' folder found and no subfolders exist under $wallBaseDIR, exiting..."
        exit 1
    fi
    echo "'16-9' folder not found, falling back to: $wallDIR"
fi

#create array of all wallpapers in the directory
PICS=($(find -L ${wallDIR} -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.pnm" -o -name "*.tga" -o -name "*.tiff" -o -name "*.webp" -o -name "*.bmp" -o -name "*.farbfeld" -o -name "*.gif" \)))

# -----------------------------------------------------------------
# 1️⃣ check if argument is given and if it is random or a file
# -----------------------------------------------------------------

#check if argument is given
if [ -z "$1" ]; then
    echo "No needed argument given, exiting..."
    exit 1
fi

#check if argument is random or a file
if [ "$1" == "random" ]; then
    echo "Selecting random wallpaper from directory: $wallDIR"
    #get current wallpaper to avoid repetition
    wallpaper_path=$(readlink -f $HOME/.config/WallpaperChanger/.current_wallpaper)
    wallpaper_path=${wallpaper_path#*$HOME/Pictures/wallpapers/}
    wallpaper_path=$(echo "$wallpaper_path" | sed 's,^[^/]*/,,')
    wallpaper_path="/$wallpaper_path"

    WallpaperRelativePath=$wallpaper_path

    #chooses new image until it is different from current one
    while [ "$WallpaperRelativePath" == "$wallpaper_path" ]
    do
        WallpaperRelativePath=${PICS[ $RANDOM % ${#PICS[@]} ]}
        WallpaperRelativePath=${WallpaperRelativePath#*$HOME/Pictures/wallpapers/}
        WallpaperRelativePath=$(echo "$WallpaperRelativePath" | sed 's,^[^/]*/,,')
        WallpaperRelativePath="/$WallpaperRelativePath"

        if ! [ -z "$2" ]; then
            if [ "$2" == "nsfw" ] && [[ "$WallpaperRelativePath" != *"nsfw"* ]]; then
                WallpaperRelativePath=$wallpaper_path
            elif [ "$2" == "sfw" ] && [[ "$WallpaperRelativePath" == *"nsfw"* ]]; then
                WallpaperRelativePath=$wallpaper_path
            fi
        fi
    done
    echo "Selected wallpaper: $WallpaperRelativePath"
else
    echo "Using given wallpaper: $1"
    WallpaperRelativePath=$1
fi

notify-send -i "$wallDIR$WallpaperRelativePath" "Changing wallpaper" "Selected wallpaper: $WallpaperRelativePath" -t 3000

# -----------------------------------------------------------------
# 2️⃣ Get connected displays and resolutions and maps them to arrays
# -----------------------------------------------------------------

#Get connected displays and resolutions and maps them to arrays
displays=$(xrandr --query | awk '/ connected/{print $1}')
mapfile -t -O 1 var < <(echo "$displays")

resolutions=$(xrandr --current | grep '*' | uniq | awk '{print $1}')
mapfile -t -O 1 res < <(echo "$resolutions")

# -----------------------------------------------------------------
# 3️⃣ Loop through displays, get aspect ratio folder, apply wallpaper with awww and set current wallpaper symlink to the one on the primary display
# -----------------------------------------------------------------

n=1
symlinkSet=false
while [[ -n ${var[$n]} ]]; do
    screen=${var[$n]}
    screen=$(echo $screen | tr -d ' ')

    resolutionAndRefreshRate=${res[$n]}
    resolutionAndRefreshRate=$(echo $resolutionAndRefreshRate | tr -d ' ')
    
    refreshRate=$(cut -d '@' -f2 <<< $resolutionAndRefreshRate)
    refreshRate=$(cut -d 'a' -f1 <<< $refreshRate)
    [ -n "${refreshRate##*.*[1-9]*}" ]
    refreshRate=$(echo $(( ${refreshRate%.*} + $? )))

    resolution=$(cut -d '@' -f1 <<< $resolutionAndRefreshRate)

    echo "Changing wallpapers on display: $screen"
    echo "with resolution: $resolution"
    echo "and refresh rate: $refreshRate"

    AspectRatioFolder=$($HOME/.config/WallpaperChanger/AspectRatioChecker.sh $resolution)
    Wallpaper=$AspectRatioFolder$WallpaperRelativePath

    # Transition config
    TYPE="any"
    DURATION=1
    BEZIER=".43,1.19,1,.4"
    AWWW_PARAMS="--transition-fps $refreshRate --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

    #transition wallpaper on display
    awww query || awww-daemon --format xrgb && awww img -o $screen $Wallpaper $AWWW_PARAMS

    if [[ $primary == $screen ]]; then
            ln -sf $Wallpaper $HOME/.config/WallpaperChanger/.current_wallpaper
            symlinkSet=true
    fi
    ((n++))
done

if [ "$symlinkSet" = false ]; then
    echo "No primary display detected via xrandr — falling back to the 16-9 version of the wallpaper for .current_wallpaper."
    ln -sf "$wallDIR$WallpaperRelativePath" "$HOME/.config/WallpaperChanger/.current_wallpaper"
fi

# -----------------------------------------------------------------
# 4️⃣ Refresh the theme
# -----------------------------------------------------------------

$HOME/.config/WallpaperChanger/themeRefresher.sh --full