TO DO:

expand collection
 - [ ] add aspect ratios
   - [ ] horizonltal
     - [x] 16:9
     - [x] 32:9 
     - [x] 21:9
     - [ ] 4:3
     - [x] 16:10
     - [ ] 21:10
     - [ ] 32:10
     - [ ] 3:2
    - [ ] vertical
      - [ ] 9:16
      - [ ] ~~9:21~~
      - [ ] ~~9:32~~
      - [ ] 3:4
      - [ ] 10:16
      - [ ] ~~10:21~~
      - [ ] ~~10:32~~
      - [ ] 2:3
- [x] implement aspect ratio checker for windows as well as rgb sync with [OpenRGB](https://openrgb.org/)
- [x] add Windows install script
- [x] add fallback to closest aspect ratio on Linux 

# Installation

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

