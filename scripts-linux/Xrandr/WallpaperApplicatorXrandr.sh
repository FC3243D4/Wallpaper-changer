#!/usr/bin/env bash
# WallpaperApplicatorXrandr.sh (Xrandr)
# Applies a wallpaper across all connected displays via awww, at each
# display's closest-matching aspect ratio, and refreshes the theme.
# Usage: WallpaperApplicatorXrandr.sh <random|relative/path/to/wallpaper.jpg> [sfw|nsfw]

# Get primary display to set the .current_wallpaper symlink to the correct one
primary=$(xrandr | grep primary)
primary=${primary%%[[:space:]]*}

echo "Running WallpaperRandomSelect.sh with arguments: $1 $2"

wallBaseDir="$HOME/Pictures/wallpapers"
if [ -d "$wallBaseDir/16-9" ]; then
    wallDir="$wallBaseDir/16-9"
else
    wallDir=$(find "$wallBaseDir" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)
    if [ -z "$wallDir" ]; then
        echo "No '16-9' folder found and no subfolders exist under $wallBaseDir, exiting..."
        exit 1
    fi
    echo "'16-9' folder not found, falling back to: $wallDir"
fi

# Build array of all wallpapers in the directory
pics=($(find -L ${wallDir} -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.pnm" -o -name "*.tga" -o -name "*.tiff" -o -name "*.webp" -o -name "*.bmp" -o -name "*.farbfeld" -o -name "*.gif" \)))

# 1. Check the argument: given file, or "random"?
if [ -z "$1" ]; then
    echo "No needed argument given, exiting..."
    exit 1
fi

if [ "$1" == "random" ]; then
    echo "Selecting random wallpaper from directory: $wallDir"
    # Get current wallpaper to avoid repetition
    wallpaperPath=$(readlink -f $HOME/.config/WallpaperChanger/.current_wallpaper)
    wallpaperPath=${wallpaperPath#*$HOME/Pictures/wallpapers/}
    wallpaperPath=$(echo "$wallpaperPath" | sed 's,^[^/]*/,,')
    wallpaperPath="/$wallpaperPath"

    wallpaperRelativePath=$wallpaperPath

    # Choose a new image until it differs from the current one
    while [ "$wallpaperRelativePath" == "$wallpaperPath" ]
    do
        wallpaperRelativePath=${pics[ $RANDOM % ${#pics[@]} ]}
        wallpaperRelativePath=${wallpaperRelativePath#*$HOME/Pictures/wallpapers/}
        wallpaperRelativePath=$(echo "$wallpaperRelativePath" | sed 's,^[^/]*/,,')
        wallpaperRelativePath="/$wallpaperRelativePath"

        if ! [ -z "$2" ]; then
            if [ "$2" == "nsfw" ] && [[ "$wallpaperRelativePath" != *"nsfw"* ]]; then
                wallpaperRelativePath=$wallpaperPath
            elif [ "$2" == "sfw" ] && [[ "$wallpaperRelativePath" == *"nsfw"* ]]; then
                wallpaperRelativePath=$wallpaperPath
            fi
        fi
    done
    echo "Selected wallpaper: $wallpaperRelativePath"
else
    echo "Using given wallpaper: $1"
    wallpaperRelativePath=$1
fi

notify-send -i "$wallDir$wallpaperRelativePath" "Changing wallpaper" "Selected wallpaper: $wallpaperRelativePath" -t 3000

# 2. Get connected displays and resolutions, mapped into parallel arrays
displays=$(xrandr --query | awk '/ connected/{print $1}')
mapfile -t -O 1 displayNames < <(echo "$displays")

resolutions=$(xrandr --current | grep '*' | uniq | awk '{print $1}')
mapfile -t -O 1 displayRes < <(echo "$resolutions")

# 3. Loop through displays, resolve the aspect-ratio folder for each, apply
# the wallpaper via awww, and point .current_wallpaper at the primary display's copy
n=1
symlinkSet=false
while [[ -n ${displayNames[$n]} ]]; do
    screen=${displayNames[$n]}
    screen=$(echo $screen | tr -d ' ')

    resolutionAndRefreshRate=${displayRes[$n]}
    resolutionAndRefreshRate=$(echo $resolutionAndRefreshRate | tr -d ' ')

    refreshRate=$(cut -d '@' -f2 <<< $resolutionAndRefreshRate)
    refreshRate=$(cut -d 'a' -f1 <<< $refreshRate)
    [ -n "${refreshRate##*.*[1-9]*}" ]
    refreshRate=$(echo $(( ${refreshRate%.*} + $? )))

    resolution=$(cut -d '@' -f1 <<< $resolutionAndRefreshRate)

    echo "Changing wallpapers on display: $screen"
    echo "with resolution: $resolution"
    echo "and refresh rate: $refreshRate"

    aspectRatioFolder=$($HOME/.config/WallpaperChanger/AspectRatioChecker.sh $resolution)
    wallpaper=$aspectRatioFolder$wallpaperRelativePath

    # Transition config
    transitionType="any"
    transitionDuration=1
    transitionBezier=".43,1.19,1,.4"
    awwwParams="--transition-fps $refreshRate --transition-type $transitionType --transition-duration $transitionDuration --transition-bezier $transitionBezier"

    # Transition wallpaper on display
    awww query || awww-daemon --format xrgb && awww img -o $screen $wallpaper $awwwParams

    if [[ $primary == $screen ]]; then
            ln -sf $wallpaper $HOME/.config/WallpaperChanger/.current_wallpaper
            symlinkSet=true
    fi
    ((n++))
done

if [ "$symlinkSet" = false ]; then
    echo "No primary display detected via xrandr — falling back to the 16-9 version of the wallpaper for .current_wallpaper."
    ln -sf "$wallDir$wallpaperRelativePath" "$HOME/.config/WallpaperChanger/.current_wallpaper"
fi

# 4. Refresh the theme
$HOME/.config/WallpaperChanger/themeRefresher.sh --full