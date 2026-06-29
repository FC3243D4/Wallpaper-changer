# Installation

On both OSs if you wish to automatically set the color of your rgb you have to use [OpenRGB](https://openrgb.org/)

## Linux
Make sure that the install.sh file is executable and run it
```
chmod +x install-Linux.sh
./install-Linux.sh
```
Any dependency will be checked by the script and it will inform you if there are missing ones

To ensure the script works at its best please remember to configure [matugen](https://github.com/InioX/matugen) on your system

## Windows
 - Make sure you installed [wallpaper engine through steam](https://store.steampowered.com/app/431960/Wallpaper_Engine/) on your C drive, if not the script will fail
 - If you also walt to use the hotkey to run the script be sure to have [autohotkey](https://www.autohotkey.com/) installed
 - Go into the folder where you cloned the repo
 - Open a cmd windows there and run 
   ```
   powershell.exe -ExecutionPolicy Bypass -File .\install-Windows.ps1
   ```
 - Next either start manually the hotkey by going into Documents\wallpaperScripts and double click on it or logout and login again and it will start automatically
