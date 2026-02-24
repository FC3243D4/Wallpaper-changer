TO DO:

expand collection
 - [ ] add aspect ratios
   - [ ] horizonltal
     - [x] 16:9
     - [x] 32:9 
     - [ ] 21:9
     - [ ] 4:3
     - [x] 16:10
     - [ ] 21:10
     - [ ] 32:10
     - [ ] 3:2
    - [ ] vertical
      - [ ] 9:16
      - [ ] 9:21
      - [ ] 9:32
      - [ ] 3:4
      - [ ] 10:16
      - [ ] 10:21
      - [ ] 10:32
      - [ ] 2:3
- [x] implement aspect ratio checker for windows as well as rgb sync
- [ ] add Windows install script
- [ ] add fallback to closest aspect ratio on Linux 

# Installation

## Linux
make sure that the install.sh file is executable and run it
```
chmod +x install.sh
./install.sh
```

## Windows
 - Make sure you installed wallpaper engine through steam on your C drive
 - Copy the files from script-windows into C:\Users\<Your username>\wallpaperScripts, you can see what's your C:\User\<Your Username> by opening a CMD windows and running
   ```
   echo %USERPROFILE%
   ```
 - Copy the wallpapers into the C:\Users\<Your username>\Pictures\wallpapers folder by copying the aspect ratios folder into it, if you want to add the nsfw variants just copy the aspect ratios folder inside the nsfw folder into C:\Users\<Your username>\Pictures\wallpapers as well

