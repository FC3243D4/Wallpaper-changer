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

if ! [ -f $HOME/.config/hypr/scripts/Refresh.sh ]; then
    echo "did not find Refresh.sh. Please make sure you installed https://github.com/JaKooLit dotfiles correctly"
    echo ""
    Stop=true
fi

if openrgb -v foo &> /dev/null ; then
    echo "openrgb is not installed. You will not have the wallpapers dominant color applied to your devices. Please install openrgb if you want this feature."
    echo ""
fi

if [ -d $HOME/.config/WallpaperChanger ]; then
    read -p "Directory $HOME/.config/WallpaperChanger exists. Do you want to delete it and all its content? [y/n]" -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        ConfigDirExists=true
        read -p "Do you still want to copy this repo's scripts to the directory? [y/n]" -n 1 -r
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
        read -p "Directory $HOME/Pictures/wallpapers exists. Do you want to delete it and all its content? [y/n]" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            WallpapersDirExists=true
            read -p "Do you still want to copy this repo's wallpapers to the directory? [y/n]" -n 1 -r
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
    read -p "Pictures directory does not exist. This can be because of your system language or because you deleted it. Do you want to create it? [y/n]" -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        CopyWallpapers=false
        WallpapersDirExists=false
    else
        CreatePicturesDir=true
        read -p "Do you want to copy this repo's wallpapers to the directory? [y/n]" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            CopyWallpapers=true
        else
            CopyWallpapers=false
        fi
    fi
fi

if [ "$Stop" = true ]; then
    echo "Installation stopped due to the above errors. Please fix them and run the script again."
    echo ""
    exit 1
fi

if [ "$ConfigDirExists" = true ]; then
    if [ "$CopyScripts" = true ]; then
        #copy correct scripts based on display utility availability
        if [ "$UseXrandr" = true ]; then
            cp ./scripts/WallpaperAspectRatioXrandr.sh $HOME/.config/WallpaperChanger/
            cp ./scripts/WallpaperRandomSelectXrandr.sh $HOME/.config/WallpaperChanger/
            cp ./scripts/WallpaperMenutXrandr.sh $HOME/.config/WallpaperChanger/
            cp ./scripts/WallpaperRandomAutoXrandr.sh $HOME/.config/WallpaperChanger/
        else
            cp ./scripts/WallpaperAspectRatio.sh $HOME/.config/WallpaperChanger/
            cp ./scripts/WallpaperRandomSelect.sh $HOME/.config/WallpaperChanger/
            cp ./scripts/WallpaperMenu.sh $HOME/.config/WallpaperChanger/
            cp ./scripts/WallpaperRandomAuto.sh $HOME/.config/WallpaperChanger/
        fi
        #copy display utility agnostic scripts
        cp ./scripts/AspectRatioChecker.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperApplicator.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/dominantcolor $HOME/.config/WallpaperChanger/

        #make them all executables
        chmod +x $HOME/.config/WallpaperChanger/*
    fi
else
    mkdir $HOME/.config/WallpaperChanger
    #copy correct scripts based on display utility availability
    if [ "$UseXrandr" = true ]; then
        cp ./scripts/WallpaperAspectRatioXrandr.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperRandomSelectXrandr.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperMenutXrandr.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperRandomAutoXrandr.sh $HOME/.config/WallpaperChanger/
    else
        cp ./scripts/WallpaperAspectRatio.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperRandomSelect.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperMenu.sh $HOME/.config/WallpaperChanger/
        cp ./scripts/WallpaperRandomAuto.sh $HOME/.config/WallpaperChanger/
    fi
    #copy display utility agnostic scripts
    cp ./scripts/AspectRatioChecker.sh $HOME/.config/WallpaperChanger/
    cp ./scripts/WallpaperApplicator.sh $HOME/.config/WallpaperChanger/
    cp ./scripts/dominantcolor $HOME/.config/WallpaperChanger/

    #make them all executables
    chmod +x $HOME/.config/WallpaperChanger/*
fi


if [ "$CreatePicturesDir" = true ]; then
    mkdir $HOME/Pictures
    mkdir $HOME/Pictures/wallpapers
else
    if [ "$WallpapersDirExists" = false ]; then
        mkdir $HOME/Pictures/wallpapers
    fi
fi

if [ "$CopyWallpapers" = true ]; then
    read -p "Do you want to copy only the sfw wallpapers? [y/n]" -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        CopyNsfw=true
    else
        CopyNsfw=false
    fi
    #copy wallpapers x:9
    if [ -d ./16-9 ]; then
        cp -r ./16-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./21-9 ]; then
        cp -r ./21-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./32-9 ]; then
        cp -r ./32-9 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./4-3 ]; then
        cp -r ./4-3 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers x:10
    if [ -d ./16-10 ]; then
        cp -r ./16-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./21-10 ]; then
        cp -r ./21-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./32-10 ]; then
        cp -r ./32-10 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./3-2 ]; then
        cp -r ./3-2 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers 9:x
    if [ -d ./9-16 ]; then
        cp -r ./9-16 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./9-21 ]; then
        cp -r ./9-21 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./9-32 ]; then
        cp -r ./9-32 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./3-4 ]; then
        cp -r ./3-4 $HOME/Pictures/wallpapers/
    fi

    #copy wallpapers 10:x
    if [ -d ./10-16 ]; then
        cp -r ./10-16 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./10-21 ]; then
        cp -r ./10-21 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./10-32 ]; then
        cp -r ./10-32 $HOME/Pictures/wallpapers/
    fi

    if [ -d ./2-3 ]; then
        cp -r ./2-3 $HOME/Pictures/wallpapers/
    fi

    #copy nsfw variants
    if [ "$CopyNsfw" = true ]; then
        #copy wallpapers x:9
        if [ -d ./nsfw/16-9 ]; then
            cp -r ./nsfw/16-9 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./21-9 ]; then
            cp -r ./nsfw/21-9 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./32-9 ]; then
            cp -r ./nsfw/32-9 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./4-3 ]; then
            cp -r ./nsfw/4-3 $HOME/Pictures/wallpapers/
        fi

        #copy wallpapers x:10
        if [ -d ./16-10 ]; then
            cp -r ./nsfw/16-10 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./21-10 ]; then
            cp -r ./nsfw/21-10 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./32-10 ]; then
            cp -r ./nsfw/32-10 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./3-2 ]; then
            cp -r ./nsfw/3-2 $HOME/Pictures/wallpapers/
        fi

        #copy wallpapers 9:x
        if [ -d ./9-16 ]; then
            cp -r ./nsfw/9-16 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./9-21 ]; then
            cp -r ./nsfw/9-21 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./9-32 ]; then
            cp -r ./nsfw/9-32 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./3-4 ]; then
            cp -r ./nsfw/3-4 $HOME/Pictures/wallpapers/
        fi

        #copy wallpapers 10:x
        if [ -d ./10-16 ]; then
            cp -r ./nsfw/10-16 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./10-21 ]; then
            cp -r ./nsfw/10-21 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./10-32 ]; then
            cp -r ./nsfw/10-32 $HOME/Pictures/wallpapers/
        fi

        if [ -d ./2-3 ]; then
            cp -r ./nsfw/2-3 $HOME/Pictures/wallpapers/
        fi
    fi
fi

if [ "$UseXrandr" = true ]; then
    echo "Installation complete."
    echo ""
    echo "You can run the wallpaper menu with $HOME/.config/WallpaperChanger/WallpaperMenuXrandr.sh to select a wallpaper"
    echo ""
    echo "You can run $HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh to start the automatic random wallpaper changer every 30min (if you want to change the interval edit the script)"
    echo ""
    echo "You can apply a random wallpaper with $HOME/.config/WallpaperChanger/WallpaperRandomSelectXrandr.sh"
    echo ""
    echo "In all cases the wallpaper will be applied to all your displays with the correct aspect ratio and the dominant color will be applied to your openrgb supported devices. If you have any issues please open an issue on the github repository"
else
    echo "Installation complete."
    echo ""
    echo "You can run the wallpaper menu with $HOME/.config/WallpaperChanger/WallpaperMenu.sh to select a wallpaper"
    echo ""
    echo "You can run $HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh to start the automatic random wallpaper changer every 30min (if you want to change the interval edit the script)"
    echo ""
    echo "You can apply a random wallpaper with $HOME/.config/WallpaperChanger/WallpaperRandomSelect.sh"
    echo ""
    echo "In all cases the wallpaper will be applied to all your displays with the correct aspect ratio and the dominant color will be applied to your openrgb supported devices. If you have any issues please open an issue on the github repository"
fi