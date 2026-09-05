# Installation

On both OSs if you wish to automatically set the color of your rgb you have to use [OpenRGB](https://openrgb.org/)

## Linux
Make sure that the install.sh file is executable and run it
```
chmod +x Install-Linux.sh
./Install-Linux.sh --install
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

# Usage on Linux

Once installed, the day-to-day entry point on Linux is `ThemeRefresher.sh` (found in `~/.config/WallpaperChanger/`), which picks an accent color from your current wallpaper and applies it system-wide. It supports three modes:

```
./ThemeRefresher.sh --full      # full refresh: theming, icons, RGB, AND restarts affected apps
./ThemeRefresher.sh --rgb       # apply the accent color to RGB devices only
./ThemeRefresher.sh --softrun   # theming, icons, and RGB, but does not restart any apps
```

`--full` is the most thorough option — it also restarts apps whose running instance needs to pick up the new theme, and (on Hyprland) restarts Waybar.

## Hyprland Layout Preservation

Restarting apps to apply a new theme inevitably scatters your windows. On Hyprland, `--full` automatically saves your current window layout beforehand and restores it afterward, using `HyprLayoutPreservation.sh` (in the same support scripts folder). This happens transparently — no extra setup needed to just use `--full` as-is.

It supports **all four Hyprland layouts** — `master`, `dwindle`, `scrolling`, and `monocle` — including **mixed setups where different workspaces use different layouts simultaneously**. By default every workspace is assumed to use whatever `general:layout` is currently set to, but you can override this per-workspace by adding a `layout` field to a workspace rule in `~/.config/hypr/UserConfigs/WorkSpaceRules.lua`, following standard Hyprland Lua syntax:

```lua
hl.workspace_rule({ workspace = "2", layout = "master" })
hl.workspace_rule({ workspace = "5", layout = "dwindle" })
hl.workspace_rule({ workspace = "7", layout = "scrolling" })
hl.workspace_rule({ workspace = "9", layout = "monocle" })
```

Any workspace without a matching rule falls back to the global default. Commented-out rules (both `--` and `--[[ ]]` style) are correctly ignored.

One thing worth knowing: for every layout except `monocle`, saving is completely passive — it just reads window positions, with no visible side effects. `monocle` is the exception: since every window in a monocle stack occupies the exact same space, there's no positional information to read, and no way to query the stack order directly. To capture it, the save step briefly switches to each monocle workspace and cycles through its windows to record the order, then returns you to wherever you started. You'll see a brief flash on monocle workspaces specifically when saving; every other layout is unaffected.

Layout restoration can also be run manually, independent of `ThemeRefresher.sh`:

```
HyprLayoutPreservation.sh save      # snapshot the current layout of every workspace
HyprLayoutPreservation.sh restore   # restore the most recent snapshot
```

## Wallpaper Thumbnails

Rofi's wallpaper menu can get slow to render once you have a lot of wallpapers, since it has to generate a thumbnail on the fly every time. Running:

```
./Install-Linux.sh --thumbnails
```

installs a systemd user watcher that pre-generates thumbnails in the background whenever wallpapers are added or changed, so the menu stays snappy. It automatically detects whichever aspect-ratio folders exist under `~/Pictures/wallpapers` — no manual configuration needed, and it stays in sync automatically if you later add wallpapers via `--update-wallpapers`.

## Icons

This repo ships the monochrome icon set used by `ThemeRefresher.sh`'s icon patching step (and by the icon patchers in [hypr-dotfiles](https://github.com/FC3243D4/hypr-dotfiles), which consumes this set rather than shipping its own). Most icons come from [Tabler Icons](https://tabler.io/icons), used under the [MIT License](https://github.com/tabler/tabler-icons/blob/main/LICENSE), with no modifications to the icon shapes themselves beyond recoloring to the current accent color. A number of icons (mainly per-game/per-app overrides not covered by Tabler's set) are custom-made.