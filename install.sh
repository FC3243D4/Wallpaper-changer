#!/usr/bin/env bash

Stop=false
HyprctlInstalled=true
UseXrandr=false

if hyprctl -v foo &> /dev/null; then
    HyprctlInstalled=false
    if ! xrandr -v foo &> /dev/nu; then
        echo "Neither hyprctl nor xrandr is installed. Please install one of them before running this script."
        Stop=true
    else
        echo "hyprctl is not installed. The script will need to use xrandr instead."
        UseXrandr=true
    fi
fi

if magick -v foo &> /dev/null; then
    echo "ImageMagick is not installed. Please install ImageMagick before running this script."
    Stop=true
fi

if wallust -v foo &> /dev/null; then
    echo "wallust is not installed. Please install wallust before running this script."
    Stop=true
fi

if awww -v foo &> /dev/null; then
    echo "awww is not installed. Please install awww before running this script."
    Stop=true
fi

if ! [ -f $HOME/.config/hypr/scripts/Refresh.sh ]; then
  echo "did not find Refresh.sh. Please make sure you installed https://github.com/JaKooLit dotfiles correctly"
  Stop=true
fi

if openrgb -v foo &> /dev/null ; then
    echo "openrgb is not installed. You will not have the wallpapers dominant color applied to your devices. Please install openrgb if you want this feature."
fi

if [ -d $HOME/.config/WallpaperChanger ]; then
  echo "Directory exists $HOME/.config/WallpaperChanger. If you want to reinstall, please delete the directory first. If you want to keep its content, please move it to a different location and delete the directory, then run this script again."
  Stop=true
else
    mkdir $HOME/.config/WallpaperChanger
fi

if [ -d $HOME/Pictures ]; then
    if [ -d $HOME/Pictures/wallpapers ]; then
        echo "Directory exists $HOME/Pictures/wallpapers. if you want to keep its content please rename it or move it to a different location, then run this script again. If you want to replace it, please delete the directory and run this script again."
        Stop=true
        else
        mkdir $HOME/Pictures/wallpapers
    fi
    else
        echo "Pictures directory does not exist. This can be because of your system language or because you deleted it. the directory will be created"
        mkdir $HOME/Pictures
        mkdir $HOME/Pictures/wallpapers
fi

if [ "$Stop" = true ]; then
    echo "Installation stopped due to the above errors. Please fix them and run the script again."
    exit 1
fi

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

if [ "$UseXrandr" = true ]; then
    echo "Installation complete. You can run the wallpaper menu with $HOME/.config/WallpaperChanger/WallpaperMenuXrandr.sh to select a wallpaper, or you can run $HOME/.config/WallpaperChanger/WallpaperRandomAutoXrandr.sh to start the automatic random wallpaper changer every 30min (if you want to change the interval edit the script). You can apply a random wallpaper with $HOME/.config/WallpaperChanger/WallpaperRandomSelectXrandr.sh. In all cases the wallpaper will be applied to all your displays with the correct aspect ratio and the dominant color will be applied to your openrgb supported devices. If you have any issues please open an issue on the github repository"
else
    echo "Installation complete. You can run the wallpaper menu with $HOME/.config/WallpaperChanger/WallpaperMenu.sh to select a wallpaper, or you can run $HOME/.config/WallpaperChanger/WallpaperRandomAuto.sh to start the automatic random wallpaper changer every 30min (if you want to change the interval edit the script). You can apply a random wallpaper with $HOME/.config/WallpaperChanger/WallpaperRandomSelect.sh. In all cases the wallpaper will be applied to all your displays with the correct aspect ratio and the dominant color will be applied to your openrgb supported devices. If you have any issues please open an issue on the github repository"
fi



