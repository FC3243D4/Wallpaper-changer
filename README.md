# Installation

On both OSs if you wish to automatically set the color of your rgb you have to use [OpenRGB](https://openrgb.org/)

## Linux
make sure that the install.sh file is executable and run it
```
chmod +x install-Linux.sh
./install-Linux.sh
```
Right now the script depends on the [dotfiles from JaKooLit](https://github.com/JaKooLit/Hyprland-Dots) for the refresh script and many configs, maybe in the future I will try and remove this dependency but for now please install them on your system
any other dependency will be checked by the script and it will inform you if there are missing ones

## Windows
 - make sure you installed [wallpaper engine through steam](https://store.steampowered.com/app/431960/Wallpaper_Engine/) on your C drive, if not the script will fail
 - if you also walt to use the hotkey to run the script be sure to have [autohotkey](https://www.autohotkey.com/) installed
 - go into the folder where you cloned the repo
 - open a cmd windows there and run 
   ```
   powershell.exe -ExecutionPolicy Bypass -File .\install-Windows.ps1
   ```
 - next either start manually the hotkey by going into Documents\wallpaperScripts and double click on it or logout and login again ad it will start automatically
