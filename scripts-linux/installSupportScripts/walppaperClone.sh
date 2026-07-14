#!/usr/bin/env bash

read -p "Do you want to clone a repo's wallpapers or provide your own for this script? [y/N]"
echo ""
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0;
else
    cat <<EOF
The wallpapers folder should be structured like this

wallpapers
|--sfw
    |--16-9 <- base directory of wallpaperApplicator
    |--21-9 <- or any other aspect ratio you want
    |--...
|--nsfw
    |--16-9
    |--21-9
    |--...

Also there are some rules that the files have to follow:
- All the wallpapers must have a variant with the same name in all aspect ratio folders
- All the files inside the nsfw parent folder must be named nsfw-<name of the wallpaper>
- The files must be one of this formats:
    - jpg
    - jpeg
    - png
    - pnm
    - tga
    - tiff
    - webp
    - bmp
    - farbfeld
    - gif

IF ANY OF THESE CONDITIONS ARE NOT MET THE SCRIPTS WILL NOT FUNCTION PROPERLY 
EOF
    read -p "Do you want to procede? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    else
        options=("provide my own" "git repo's" "cancel")

        echo "Choose the way you wish to procede:"
        select chosenOption in "${options[@]}"; do
            if [ -n "$chosenOption" ]; then
                echo "You chose: $chosenOption"
                break
            else
                echo "Invalid choice, try again."
            fi
        done

        if [ "$chosenOption" == "provide my own" ]; then
            mkdir ./wallpapers
            echo "Please place your wallpapers into the wallpapers folder now, following the structure and rules shown above. If you wish to cancel the operation simply delete the wallpapers folder and procede"
            read -p "Press enter once you're done adding your wallpapers..." -r
            echo ""
        elif [ "$chosenOption" == "git repo's" ]; then
            read -p "Please paste here the repo's link: " wallpaperRepo
            echo ""
            echo ""
            if [ -n "$wallpaperRepo" ]; then
                git clone "$wallpaperRepo" ./wallpapers
            fi
        fi
    fi
fi