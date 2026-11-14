# Installation

On both OSs if you wish to automatically set the color of your rgb you have to use [OpenRGB](https://openrgb.org/)

## Linux
Make sure that the Install-Linux.sh file is executable and run it
```
chmod +x Install-Linux.sh
./Install-Linux.sh --install
```
Any dependency will be checked by the script and it will inform you if there are missing ones

To ensure the script works at its best please remember to configure [matugen](https://github.com/InioX/matugen) on your system

## Windows
Requirements:
 - [PowerShell 7](https://github.com/PowerShell/PowerShell) (`winget install Microsoft.PowerShell`) - the scripts run in `pwsh`, not the built-in Windows PowerShell 5.1
 - [Wallpaper Engine](https://store.steampowered.com/app/431960/Wallpaper_Engine/) - found automatically in any Steam library on any drive (or set `wallpaperEngineExe` in `config.json`)
 - [matugen](https://github.com/InioX/matugen) for the theming. Upstream has no Windows binary, so it is built with Rust: the installer checks for it and, if you agree, runs `cargo install matugen --locked` (installing Rust via winget first when needed)
 - optional: [File Pilot](https://filepilot.tech) (the installer offers it via winget; proprietary, free during its beta), [OpenRGB](https://openrgb.org/) for RGB, [AutoHotkey v2](https://www.autohotkey.com/) for the keyboard shortcuts (the installer offers it via winget), Python + `pip install PyQt6` for the wallpaper picker GUI

Install - from the repo root (works from `powershell.exe` too: the installer re-launches itself in PowerShell 7 and offers to install it):
```
powershell.exe -ExecutionPolicy Bypass -File .\install-Windows.ps1
```
`-Yes` answers yes to the dependency prompts, `-NonInteractive` only reports what is missing. Everything lands in `%LOCALAPPDATA%\WallpaperChanger`; re-running updates the scripts and keeps `config.json` and the caches. Wallpapers go in `%USERPROFILE%\Pictures\wallpapers\<aspect-ratio>\` (16-9, 21-9, ...), same layout as on Linux.

# Usage on Windows

```
pwsh -File "$env:LOCALAPPDATA\WallpaperChanger\setRandomWallpaper-WE.ps1"                 # random wallpaper + theme refresh
pwsh -File ... setRandomWallpaper-WE.ps1 -Filter Sfw                                        # or Nsfw (also: setRandomWallpaper-WE-SFW/NSFW.ps1)
pwsh -File ... setRandomWallpaper-WE.ps1 -Wallpaper 'series\image.png'                      # a specific one, on every monitor
pwsh -File ... ThemeRefresher.ps1 -Mode Full|Softrun|Rgb                                    # re-theme from the current wallpaper only
python "$env:LOCALAPPDATA\WallpaperChanger\WallpaperGui.py"                                # picker GUI (same file as on Linux)
```
Keyboard shortcuts (AutoHotkey v2, started at login by the installer): `Win+Shift+W` random wallpaper, `Win+Ctrl+Shift+W` random SFW, `Win+Shift+Alt+W` random NSFW, `Win+W` picker GUI (press again to close it). Presses while a run is still in progress are ignored, and a failed run shows a notification. `Win+W` replaces Windows' Widgets shortcut while the script runs; the bindings are in the HOTKEYS block of `wallpaperHotkey.ahk`.

`ThemeRefresher.ps1` mirrors the Linux modes: `Full` closes the apps that cache their theme (VS Code, Vesktop, Ferdium, SourceGit, Thunderbird/Betterbird, Spotify via Spicetify), patches everything in parallel and relaunches only the apps that were running; `Softrun` never closes anything; `Rgb` only recolors RGB. Only apps that are installed are touched: VS Code, Vesktop, Ferdium icons, SourceGit, Firefox, Zen, Thunderbird/Betterbird, Spicetify and Heroic (via the same matugen templates as on Linux). The system accent color is left to Wallpaper Engine.

Settings live in `%LOCALAPPDATA%\WallpaperChanger\config.json`: `wallpaperDir`, `wallpaperEngineExe`, `openRgbExe`, `openRgbPort`, `rgbEnabled`, and `refreshMode` (`Full` | `Softrun` | `Rgb` | `None`, what runs after a wallpaper change).

**RGB and administrator rights.** Some hardware (e.g. Corsair RAM) needs OpenRGB to run elevated. Run `pwsh -File "$env:LOCALAPPDATA\WallpaperChanger\Register-OpenRgbServer.ps1"` once: it registers a scheduled task that starts the OpenRGB *server* elevated at logon, and the scripts then talk to it as a normal user - no UAC prompt per wallpaper change, and nothing user-writable ever runs with admin rights. Without the task, the scripts fall back to launching OpenRGB elevated each time (one UAC prompt).

Not ported (no Windows counterpart): GTK/KDE theming, the icon theme, tray-icon patching, Waybar and Hyprland layout preservation.

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