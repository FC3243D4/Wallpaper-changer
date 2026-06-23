#!/usr/bin/env bash

Stop=false
HyprctlInstalled=true
UseXrandr=false
CreatePicturesDir=false
ConfigDirExists=false
CopyScripts=true
WallpapersDirExists=false
CopyWallpapers=true
CopyNsfw=false
wallpapersRepo=false

# -------------------------
# 1️⃣ CHECK FOR REQUIRED UTILITIES
# -------------------------


if hyprctl -v foo &> /dev/null; then
    HyprctlInstalled=false
    if ! xrandr -v foo &> /dev/null; then
        echo "Neither hyprctl nor xrandr is installed. Please install one of them before running this script."
        echo ""
        Stop=true
    else
        echo "hyprctl is not installed. The script will need to use xrandr instead."
        echo ""
        UseXrandr=true
    fi
fi

if xrandr -v foo &> /dev/null; then
    if ! xrandr | grep primary &> /dev/null; then
        echo "xrandr is installed but no primary display is set. to ensure the script works correctly, please set a primary display with"
        echo ""
        echo "xrandr --output <display> --primary"
        echo ""
        echo "replacing <display> with the name of your display. You can find the name of your display by running"
        echo "xrandr"
        echo ""
        echo "and looking for the connected displays. If you have multiple displays, make sure to set the correct display to ensure the script works correctly."
        echo ""
    fi
fi

if magick -v foo &> /dev/null; then
    echo "ImageMagick is not installed. Please install ImageMagick before running this script."
    echo ""
    Stop=true
fi

if wallust -v foo &> /dev/null; then
    echo "wallust is not installed. Please install wallust before running this script."
    echo ""
    Stop=true
fi

if awww -v foo &> /dev/null; then
    echo "awww is not installed. Please install awww before running this script."
    echo ""
    Stop=true
fi

# Check if package bc exists
if ! command -v bc &>/dev/null; then
    echo "bc missing. Install package bc first"
    echo ""
    Stop=true
fi

if openrgb -v foo &> /dev/null ; then
    echo "openrgb is not installed. You will not have the wallpapers dominant color applied to your devices. Please install openrgb if you want this feature."
    echo ""
fi

if [ "$Stop" = true ]; then
    echo "Installation stopped due to the above errors. Please fix them and run the script again."
    echo ""
    exit 1
fi

# -------------------------
# 2️⃣ CHECK FOR EXISTING DIRECTORIES AND FILES
# -------------------------
if [ -d $HOME/.config/WallpaperChanger ]; then
    read -p "Directory $HOME/.config/WallpaperChanger exists. Do you want to delete it and all its content? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        ConfigDirExists=true
        read -p "Do you still want to copy this repo's scripts to the directory? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            CopyScripts=false
        else
            CopyScripts=true
        fi
    else
        rm -r $HOME/.config/WallpaperChanger
    fi
fi

if [ -d $HOME/Pictures ]; then
    if [ -d $HOME/Pictures/wallpapers ]; then
        read -p "Directory $HOME/Pictures/wallpapers exists. Do you want to delete it and all its content? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            WallpapersDirExists=true
            read -p "Do you still want to copy this repo's wallpapers to the directory? [y/N]" -n 1 -r
            echo ""
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]
            then
                CopyWallpapers=false
            else
                CopyWallpapers=true
            fi
        else
            rm -r $HOME/Pictures/wallpapers
        fi
    fi
else
    read -p "Pictures directory does not exist. This can be because of your system language or because you deleted it. Do you want to create it? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        CopyWallpapers=false
        WallpapersDirExists=false
    else
        CreatePicturesDir=true
        if [ -d ./wallpapers ]; then
            wallpapersRepo=true
            read -p "Do you want to copy this repo's wallpapers to the directory? [y/N]" -n 1 -r
            echo ""
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                CopyWallpapers=false
            else
                CopyWallpapers=true
            fi
        fi
    fi
fi

if [ ! -d "$HOME/.config/rofi" ]; then
    mkdir -p $HOME/.config/rofi
fi
if [ -f "$HOME/.config/rofi/config-wallpaper.rasi" ]; then
    read -p "Rofi config for the wallpaper menu already exists. Would you like to overwrite it with the one from the repo? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp ./rofi/config-wallpaper.rasi $HOME/.config/rofi/
    fi
else
    if [ ! -d "$HOME/.config/rofi" ]; then
        mkdir -p $HOME/.config/rofi
    fi
    cp ./rofi/config-wallpaper.rasi $HOME/.config/rofi/
fi

# -------------------------
# 3️⃣ SCRIPT INSTALLATION
# -------------------------

if [ "$ConfigDirExists" = false ]; then
    mkdir $HOME/.config/WallpaperChanger
fi

if [ "$CopyScripts" = true ]; then
    #copy correct scripts based on display utility availability
    if [ "$UseXrandr" = true ]; then
        cp ./scripts-linux/Xrandr/* $HOME/.config/WallpaperChanger/
    else
        cp ./scripts-linux/hyprctl/* $HOME/.config/WallpaperChanger/
    fi
    #copy display utility agnostic scripts
    cp ./scripts-linux/AspectRatioChecker.sh $HOME/.config/WallpaperChanger/
    cp ./scripts-linux/dominantcolor $HOME/.config/WallpaperChanger/
    cp ./scripts-linux/themeRefresher.sh $HOME/.config/WallpaperChanger/

    #make them all executables
    chmod +x $HOME/.config/WallpaperChanger/*
fi

# -------------------------
# 4️⃣ WALLPAPER INSTALLATION
# -------------------------


if [ "$CreatePicturesDir" = true ]; then
    mkdir $HOME/Pictures
    mkdir $HOME/Pictures/wallpapers
else
    if [ "$WallpapersDirExists" = false ]; then
        mkdir $HOME/Pictures/wallpapers
    fi
fi


if [ "$CopyWallpapers" = true ]; then
    if [ -f "$HOME/.cache/wallpaper_ratios.cache" ]; then
        rm "$HOME/.cache/wallpaper_ratios.cache"
    fi
    read -p "Do you want to copy the nsfw wallpapers? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        CopyNsfw=false
    else
        CopyNsfw=true
    fi

    #copy wallpapers x:9
    if [ -d ./wallpapers/sfw/16-9 ]; then
        cp -r ./wallpapers/sfw/16-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/21-9 ]; then
        cp -r ./wallpapers/sfw/21-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/32-9 ]; then
        cp -r ./wallpapers/sfw/32-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/4-3 ]; then
        cp -r ./wallpapers/sfw/4-3 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers x:10
    if [ -d ./wallpapers/sfw/16-10 ]; then
        cp -r ./wallpapers/sfw/16-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/21-10 ]; then
        cp -r ./wallpapers/sfw/21-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/32-10 ]; then
        cp -r ./wallpapers/sfw/32-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/3-2 ]; then
        cp -r ./wallpapers/sfw/3-2 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers 9:x
    if [ -d ./wallpapers/sfw/9-16 ]; then
        cp -r ./wallpapers/sfw/9-16 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/9-21 ]; then
        cp -r ./wallpapers/sfw/9-21 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/9-32 ]; then
        cp -r ./wallpapers/sfw/9-32 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/3-4 ]; then
        cp -r ./wallpapers/sfw/3-4 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers 10:x
    if [ -d ./wallpapers/sfw/10-16 ]; then
        cp -r ./wallpapers/sfw/10-16 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/10-21 ]; then
        cp -r ./wallpapers/sfw/10-21 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/10-32 ]; then
        cp -r ./wallpapers/sfw/10-32 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./wallpapers/sfw/2-3 ]; then
        cp -r ./wallpapers/sfw/2-3 $HOME/Pictures/wallpapers/
    fi

    #copy nsfw variants
    if [ "$CopyNsfw" = true ]; then
        #copy wallpapers x:9
        if [ -d ./wallpapers/nsfw/16-9 ]; then
            cp -r ./wallpapers/nsfw/16-9 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/21-9 ]; then
            cp -r ./wallpapers/nsfw/21-9 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/32-9 ]; then
            cp -r ./wallpapers/nsfw/32-9 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/4-3 ]; then
            cp -r ./wallpapers/nsfw/4-3 $HOME/Pictures/wallpapers/
        fi

        #copy wallpapers x:10
        if [ -d ./wallpapers/nsfw/16-10 ]; then
            cp -r ./wallpapers/nsfw/16-10 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/21-10 ]; then
            cp -r ./wallpapers/nsfw/21-10 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/32-10 ]; then
            cp -r ./wallpapers/nsfw/32-10 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/3-2 ]; then
            cp -r ./wallpapers/nsfw/3-2 $HOME/Pictures/wallpapers/
        fi

        #copy wallpapers 9:x
        if [ -d ./wallpapers/nsfw/9-16 ]; then
            cp -r ./wallpapers/nsfw/9-16 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/9-21 ]; then
            cp -r ./wallpapers/nsfw/9-21 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/9-32 ]; then
            cp -r ./wallpapers/nsfw/9-32 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/3-4 ]; then
            cp -r ./wallpapers/nsfw/3-4 $HOME/Pictures/wallpapers/
        fi

        #copy wallpapers 10:x
        if [ -d ./wallpapers/nsfw/10-16 ]; then
            cp -r ./wallpapers/nsfw/10-16 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/10-21 ]; then
            cp -r ./wallpapers/nsfw/10-21 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/10-32 ]; then
            cp -r ./wallpapers/nsfw/10-32 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./wallpapers/nsfw/2-3 ]; then
            cp -r ./wallpapers/nsfw/2-3 $HOME/Pictures/wallpapers/
        fi
    fi
fi

# -------------------------
# 5️⃣ FINAL MESSAGE
# -------------------------

echo "Installation complete."
if [ "$UseXrandr" = true ]; then
    if [ "$CopyScripts" = true ]; then
        echo ""
        echo "You can run the wallpaper menu with $HOME/.config/WallpaperChanger/WallpaperMenuXrandr.sh to select a wallpaper"
        echo ""
        echo "You can apply a random wallpaper with"
        echo "$HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random"
        echo ""
        if [ "$CopyNsfw" = true ] && [ "$CopyScripts" = true ]; then
            echo "Since you copied the nsfw wallpapers you can also use"
            echo "$HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random sfw"
            echo "and" 
            echo "$HOME/.config/WallpaperChanger/WallpaperApplicatorXrandr.sh random nsfw" 
            echo "to only apply sfw or nsfw wallpapers as well as"
            echo "$HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh sfw"
            echo "and"
            echo "$HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh nsfw"
            echo "to do so automatically every 30min (if you want to change the interval edit the script)"
        else
            echo "You can run $HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh to start the automatic random wallpaper changer every 30min (if you want to change the interval edit the script)"
        fi
        echo ""
        echo "On its first run, the script will create a cache file with the aspect ratios of your wallpapers to speed up the process. If you add or remove wallpaper ratios, make sure to delete the cache file at $HOME/.cache/wallpaper_ratios.cache to ensure the script works correctly."
        echo ""
        echo "In all cases the wallpaper will be applied to all your displays with the correct aspect ratio and the dominant color will be applied to your openrgb supported devices."
    fi
else
    if [ "$CopyScripts" = true ]; then
        echo ""
        echo "You can run the wallpaper menu with $HOME/.config/WallpaperChanger/WallpaperMenu.sh to select a wallpaper"
        echo ""
        echo "You can run $HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh to start the automatic random wallpaper changer every 30min (if you want to change the interval edit the script)"
        echo ""
        echo "You can apply a random wallpaper with"
        echo "$HOME/.config/WallpaperChanger/WallpaperApplication.sh random"
        echo ""
        if [ "$CopyNsfw" = true ] && [ "$CopyScripts" = true ]; then
            echo "Since you copied the nsfw wallpapers you can also use"
            echo "$HOME/.config/WallpaperChanger/WallpaperApplicator.sh random sfw"
            echo "and" 
            echo "$HOME/.config/WallpaperChanger/WallpaperApplicator.sh random nsfw" 
            echo "to only apply sfw or nsfwwallpapers as well as"
            echo "$HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh sfw"
            echo "and"
            echo "$HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh nsfw"
            echo "to only apply sfw or nsfw wallpapers in the automatic random changer"
        fi
        echo ""
        echo "In all cases the wallpaper will be applied to all your displays with the correct aspect ratio and the dominant color will be applied to your openrgb supported devices."
        echo ""
        if [ "$wallpapersRepo" = false ]; then
            echo "make sure to add your own wallpapers to $HOME/Pictures/wallpapers in folders named after their aspect ratios (16-9, 21-9, ...) to ensure the script works correctly."
            echo ""
        fi
        echo "On its first run, the script will create a cache file with the aspect ratios of your wallpapers to speed up the process. If you add or remove wallpaper ratios, make sure to delete the cache file at $HOME/.cache/wallpaper_ratios.cache to ensure the script detects them correctly."
        echo ""
    fi
fi
echo "If you have any issues or want to report them, please open an issue on the github repository"