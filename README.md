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

# Usage

Once installed, the day-to-day entry point on Linux is `themeRefresher.sh` (found in `~/.config/WallpaperChanger/`), which picks an accent color from your current wallpaper and applies it system-wide. It supports three modes:

```
./themeRefresher.sh --full      # full refresh: theming, icons, RGB, AND restarts affected apps
./themeRefresher.sh --rgb       # apply the accent color to RGB devices only
./themeRefresher.sh --softrun   # theming, icons, and RGB, but does not restart any apps
```

`--full` is the most thorough option — it also restarts apps whose running instance needs to pick up the new theme, and (on Hyprland) restarts Waybar.

## Hyprland Layout Preservation

Restarting apps to apply a new theme inevitably scatters your windows. On Hyprland, `--full` automatically saves your current window layout beforehand and restores it afterward, using `hyprLayoutPreservation.sh` (in the same support scripts folder). This happens transparently — no extra setup needed to just use `--full` as-is.

It supports both the `master` and `dwindle` layouts, including **mixed setups where different workspaces use different layouts**. By default every workspace is assumed to use whatever `general:layout` is currently set to, but you can override this per-workspace by adding a `layout` field to a workspace rule in `~/.config/hypr/UserConfigs/WorkSpaceRules.lua`, following standard Hyprland Lua syntax:

```lua
hl.workspace_rule({ workspace = "2", layout = "master" })
hl.workspace_rule({ workspace = "5", layout = "dwindle" })
```

Any workspace without a matching rule falls back to the global default. Commented-out rules (both `--` and `--[[ ]]` style) are correctly ignored.

Layout restoration can also be run manually, independent of `themeRefresher.sh`:

```
hyprLayoutPreservation.sh save      # snapshot the current layout of every workspace
hyprLayoutPreservation.sh restore   # restore the most recent snapshot
```