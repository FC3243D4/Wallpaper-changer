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

# Shared helper — always recolors fresh from the base SVG using this
# script's own (waybar-corrected) $accent. Deliberately does NOT reuse
# $iconThemeDir/apps/scalable/<name>.svg even when it exists, since that
# copy was colored by IconPatcher.sh's engine with the raw wallpaper seed
# — reusing it would silently defeat the primary correction above. Costs
# a redundant recolor, but guarantees tray icons and waybar text agree.
resolve_themed_svg() {
    local name="$1"
    local base=""
    [ -f "$gameIconsDir/${name}_base_icon.svg" ] && base="$gameIconsDir/${name}_base_icon.svg"
    [ -z "$base" ] && [ -f "$iconsDir/${name}_base_icon.svg" ] && base="$iconsDir/${name}_base_icon.svg"
    [ -z "$base" ] && return 1

    local tmp
    tmp=$(mktemp --suffix=.svg)
    sed "s/currentColor/$accent/g" "$base" > "$tmp"
    echo "$tmp"
}

# fix_system_dir_permissions <dir> <label>
# One-time chown of a package-owned directory to the current user, so
# subsequent writes need no sudo at all — until the next package update
# resets ownership back to root, at which point this just redoes it.
# Non-blocking: uses `sudo -n`, so it fails fast instead of hanging when
# there's no cached credential/interactive terminal (see: the hang bug
# from an earlier version of this pattern). Ownership is otherwise kept
# in sync by TARGETS in update-and-fix.sh, which runs after every
# topgrade and re-chowns anything a package update reset to root.
fix_system_dir_permissions() {
    local dir="$1" label="$2"
    [ -w "$dir" ] && return 0
    echo "  $label: $dir is root-owned, attempting one-time chown..."
    if sudo -n chown -R "$USER" "$dir" 2>/dev/null; then
        echo "  $label: ownership fixed — future runs won't need sudo."
        echo "  (if theming silently stops updating after a $label package"
        echo "   update, that's this directory getting reset to root again — just"
        echo "   re-run this script and it'll redo the chown.)"
        return 0
    fi
    echo "  $label: couldn't chown automatically (needs an interactive sudo prompt)."
    echo "  Run this once yourself, then re-run this script:"
    echo "    sudo chown -R \$USER $dir"
    return 1
}

# time_step_bg <label> <function> — same contract as time_step, but
# backgrounds the function and prefixes every line it prints (stdout+
# stderr merged) with "[label] " so concurrent jobs' output stays
# attributable (same technique ThemeRefresher.sh's time_step_bg uses).
#
# Output is captured to a temp file, not piped live through sed: if any
# function here backgrounds+disowns work of its own without redirecting
# that work's output first (e.g. force_ytm_desktop_reload's 12s delayed
# revert — already safely redirected, but exactly the risky shape), a
# live pipe would let that orphaned writer hold the pipe open
# indefinitely, turning a fast step into a stuck one. A regular file has
# no such blocking semantics — confirmed by reproducing the failure
# against RgbApply.sh's disowned ratbagctl loop elsewhere in this pipeline.
#
# Every function below writes to a different app's own disjoint asset
# directory (blueman is the only one touching $iconThemeDir), and the
# shared helpers they call (resolve_themed_svg, fix_system_dir_permissions)
# are safe under concurrency too — so running them all in parallel is fine.
#
# Never wrap this in $(...) to grab the PID — that runs in its own
# subshell, and a job backgrounded inside it gets reparented away (not a
# waitable child of this script) once the subshell exits. Call directly,
# then read $! right after.
time_step_bg() {
    local label="$1"; shift
    local outfile
    outfile=$(mktemp)
    (
        local start end rc
        start=$(date +%s.%N)
        "$@" > "$outfile" 2>&1
        rc=$?
        end=$(date +%s.%N)
        sed "s/^/[$label] /" "$outfile"
        rm -f "$outfile"
        awk -v s="$start" -v e="$end" -v l="$label" \
            'BEGIN { printf "  [%7.3fs] %s\n", e - s, l }' >&2
        exit $rc
    ) &
}

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