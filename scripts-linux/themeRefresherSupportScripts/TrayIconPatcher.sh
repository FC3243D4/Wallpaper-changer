#!/usr/bin/env bash
# TrayIconPatcher.sh
# Themes system-tray icons for apps that don't pick up breeze-dark-accent's
# regular app-icon theming — either because they draw their tray icon from
# their own bundled asset (not looked up by name through the icon theme),
# or because they expect a literal file path in their own config, the way
# Vesktop does. Split out from IconPatcher.sh since each app needs a
# different hand-rolled approach rather than the generic .desktop engine.
#
# Called automatically from IconPatcher.sh at the end of its run, so the
# accent-colored app SVGs in $iconThemeDir/apps/scalable/ already exist.
#
# Usage: TrayIconPatcher.sh <hex_color> [--list]
#   --list   discover/report what would be touched for blueman and
#            onedrivegui without writing anything. Run this first on a new
#            machine to confirm the discovered icon names look right.

color="${1,,}"
listOnly=0
[ "${2:-}" = "--list" ] && listOnly=1

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color> [--list]" >&2
    exit 1
fi

accent="#$color"
supportDir="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
scriptSupportDir="$supportDir/trayIconPatcherSupportScripts"
iconsDir="$supportDir/svg"
gameIconsDir="$iconsDir/games"
iconThemeDir="$HOME/.local/share/icons/breeze-dark-accent"

# Sourcing utility functions file
source "$scriptSupportDir/Utils.sh"

# Sourcing files with the patching functions instead of defining them inline keeps this script readable and avoids a single massive file. Each support script is responsible for its own functions
source "$scriptSupportDir/BetterbirdTrayIconPatcher.sh"
source "$scriptSupportDir/BluemanTrayIconPatcher.sh"
source "$scriptSupportDir/CohesionTrayIconPatcher.sh"
source "$scriptSupportDir/FerdiumTrayIconPatcher.sh"
source "$scriptSupportDir/LocalsendTrayIconPatcher.sh"
source "$scriptSupportDir/NativmixTrayIconPatcher.sh"
source "$scriptSupportDir/OneDriveGuiTrayIconPatcher.sh"
source "$scriptSupportDir/SonoraTrayIconPatcher.sh"
source "$scriptSupportDir/SteamTrayIconPatcher.sh"
source "$scriptSupportDir/StreamcontrollerTrayIconPatcher.sh"
source "$scriptSupportDir/VesktopTrayIconPatcher.sh"
source "$scriptSupportDir/YtMusicTrayIconPatcher.sh"

# Match waybar's text color exactly, not just "the same seed": $color/
# $accent here is the raw hex ColorChooser.sh sampled from the wallpaper,
# but waybar's @primary is matugen's *resolved* colors.primary.default —
# a tonally-adjusted derivative of that seed, not the seed itself. Icons
# colored with the raw seed and waybar text colored with the resolved
# primary are two close-but-different colors, which is exactly why the
# mismatch stands out sitting right next to each other in the tray.
# matugen already runs before IconPatcher.sh in ThemeRefresher.sh, so the
# rendered file already has the real value — read it back instead of
# re-deriving it. Only affects tray icons; everything else in the
# pipeline still uses the raw seed.
waybarColorsRenderedFile="$HOME/.config/waybar/colors.css"
if [ -f "$waybarColorsRenderedFile" ]; then
    waybarAccent=$(grep -m1 -oP '@define-color\s+primary\s+\K#[0-9a-fA-F]{6}' "$waybarColorsRenderedFile")
    if [ -n "$waybarAccent" ]; then
        accent="$waybarAccent"
        color="${accent#\#}"
        color="${color,,}"
        echo "  tray icons: using waybar's resolved primary ($accent) instead of the raw wallpaper seed"
    else
        echo "  tray icons: primary not found in $waybarColorsRenderedFile, falling back to raw seed color"
    fi
else
    echo "  tray icons: $waybarColorsRenderedFile not found, falling back to raw seed color"
fi

# ---- Run everything ----
declare -a trayPids=()
time_step_bg "nativmix"         patch_nativmix_tray;         trayPids+=("$!")
time_step_bg "ferdium"          patch_ferdium_tray;          trayPids+=("$!")
time_step_bg "localsend"        patch_localsend_tray;        trayPids+=("$!")
time_step_bg "streamcontroller" patch_streamcontroller_tray; trayPids+=("$!")
time_step_bg "steam"            patch_steam_tray;            trayPids+=("$!")
time_step_bg "blueman"          patch_blueman_tray;          trayPids+=("$!")
time_step_bg "onedrivegui"      patch_onedrive_gui_tray;      trayPids+=("$!")
time_step_bg "vesktop"          patch_vesktop_tray;          trayPids+=("$!")
time_step_bg "ytmdesktop"       patch_ytm_desktop_tray;       trayPids+=("$!")
time_step_bg "betterbird"       patch_betterbird_tray;       trayPids+=("$!")
time_step_bg "sonora"           patch_sonora_tray;           trayPids+=("$!")
time_step_bg "cohesion"         patch_cohesion_tray;         trayPids+=("$!")

for pid in "${trayPids[@]}"; do
    wait "$pid"
done

[ "$listOnly" -eq 0 ] && echo "Tray icons patched with $accent"