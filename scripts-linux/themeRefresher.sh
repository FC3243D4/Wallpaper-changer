#!/usr/bin/env bash

#Get dominant color from wallpaper
colorLine="$($HOME/.config/WallpaperChanger/dominantcolor -m 1 -n 2 -e black -p dominant $HOME/.config/WallpaperChanger/.current_wallpaper | grep -E '#')"
color=$(echo $colorLine | tr -d '#')
echo "Dominant color: #$color"

#apply color to openrgb
if ! openrgb --version &> /dev/null; then
    echo "OpenRGB is not installed. Skipping color application."
else
    echo "OpenRGB detected. Applying dominant color to OpenRGB devices..."
    openrgb -c $color
fi

#apply color to logitech G devices
devices=($(ratbagctl list | grep -oP '^[\w-]+(?=:)'))

for device in "${devices[@]}"; do
  profiles=($(ratbagctl "$device" info | grep -oP '^Profile \K\d+'))
  for profile in "${profiles[@]}"; do
    ratbagctl "$device" profile $profile led 0 set mode on color $color
  done
done

#refresh color pallette
wallust run -s $HOME/.config/WallpaperChanger/.current_wallpaper

# Kill already running processes
_ps=(rofi swaync ags)
for _prs in "${_ps[@]}"; do
  if pidof "${_prs}" >/dev/null; then
    pkill "${_prs}"
  fi
done

# quit quickshell & relaunch quickshell
pkill qs && qs &

# some process to kill
for pid in $(pidof rofi swaync ags swaybg); do
  kill -SIGUSR1 "$pid"
  sleep 0.1
done

#Restart waybar and kill kded6 to ensure functiin of tray module
killall waybar
sleep 0.5
waybar &

# relaunch swaync
sleep 0.3
swaync >/dev/null 2>&1 &
# reload swaync
swaync-client --reload-config

#reload kitty
kill -SIGUSR1 $(pidof kitty)

sleep 2
echo "killing kded6 to refresh system tray"
pkill "kded6"