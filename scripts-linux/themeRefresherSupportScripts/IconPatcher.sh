#!/usr/bin/env bash
# IconPatcher.sh
# Patches icon SVGs in breeze-dark-accent with the accent color.
#
# v2 — merged with gamesIconPatcher.sh. Instead of one hand-written function
# per app, a generic engine scans every .desktop file and resolves an icon:
#
#   1. icon-overrides.conf[slug]         — manual override (games-style)
#   2. ${slug}_base_icon.svg             — custom icon matching the app name
#      (searched in $gameIconsDir first, then $iconsDir)
#   3. game detection                    — generic "gaming" icon
#   4. Categories= match                 — generic per-category icon
#   5. application_base_icon.svg         — last-resort catch-all (optional,
#                                          only if the file exists)
#
# Icons that need multi-tone HSV math, PNG recoloring, tray JSON, or system
# theme (breeze) patching keep their dedicated functions below; they run
# BEFORE the engine and register their .desktop files so the engine skips
# them.
#
# Manual slug -> icon overrides live in their own file, icon-overrides.conf,
# next to this script's support dir (see $iconOverridesConf below) — edit
# that file to add/remove overrides, not this script. It documents its own
# format and how to find an app's slug.
#
# Usage: IconPatcher.sh <hex_color> [--dry-run]
#   --dry-run  only run the generic engine in report mode: print
#              NAME -> slug -> icon (reason) for every .desktop file,
#              write nothing. Use this to find the slug keys to put in
#              icon-overrides.conf.

color="${1,,}"
dryRun=0
[ "${2:-}" = "--dry-run" ] && dryRun=1

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color> [--dry-run]" >&2
    exit 1
fi

accent="#$color"
iconThemeDir="$HOME/.local/share/icons/breeze-dark-accent"
supportDir="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
scriptSupportDir="$supportDir/iconPatcherSupportScripts"
iconsDir="$supportDir/svg"
gameIconsDir="$iconsDir/games"                 # drop per-game custom icons here

# Sourcing files with the patching functions instead of defining them inline keeps this script readable and avoids a single massive file. Each support script is responsible for its own functions
source "$scriptSupportDir/BreezeIconsPatcher.sh"
source "$scriptSupportDir/CachyOsIconsPatcher.sh"
source "$scriptSupportDir/ConkyIconPatcher.sh"
source "$scriptSupportDir/DesktopEntriesPatcher.sh"
source "$scriptSupportDir/DiscordVesktopIconPatcher.sh"
source "$scriptSupportDir/NativmixIconPatcher.sh"
source "$scriptSupportDir/OrcaSlicerIconPatcher.sh"
source "$scriptSupportDir/SwayIconsPatcher.sh"
source "$scriptSupportDir/WlogoutIconPatcher.sh"

# Symbolic (ColorScheme-Text) icons use matugen's resolved primary color
# rather than the raw wallpaper seed, to match tray icons/waybar text they
# sit next to (Solaar, NetworkManager, the trash icon, etc). Everything
# using ColorScheme-Accent/Highlight keeps the raw seed $accent. Falls
# back to $accent if the rendered file isn't found.
symbolicAccent="$accent"
waybarColorsRenderedFile="$HOME/.config/waybar/colors.css"
if [ -f "$waybarColorsRenderedFile" ]; then
    resolvedPrimary=$(grep -m1 -oP '@define-color\s+primary\s+\K#[0-9a-fA-F]{6}' "$waybarColorsRenderedFile")
    [ -n "$resolvedPrimary" ] && symbolicAccent="$resolvedPrimary"
fi

mkdir -p "$iconThemeDir/apps/16" "$iconThemeDir/apps/22" "$iconThemeDir/apps/24" \
         "$iconThemeDir/apps/32" "$iconThemeDir/apps/44" "$iconThemeDir/apps/48" \
         "$iconThemeDir/apps/64" "$iconThemeDir/apps/scalable" "$gameIconsDir"

# find_base_svg <iconName> — echoes the path of the matching base SVG,
# preferring per-game icons over the shared pool. Returns 1 if none exists.
find_base_svg() {
    local name="$1"
    if [ -f "$gameIconsDir/${name}_base_icon.svg" ]; then
        echo "$gameIconsDir/${name}_base_icon.svg"
    elif [ -f "$iconsDir/${name}_base_icon.svg" ]; then
        echo "$iconsDir/${name}_base_icon.svg"
    else
        return 1
    fi
}

# colorize_svg <src> <dst> <iconName>
# Recolors according to colorTokens (default: replace currentColor).
patch_svg_color() {
    local src="$1" dst="$2" name="$3"
    local tokens="${colorTokens[$name]:-currentColor}"

    if [ "$tokens" = "@inject" ]; then
        # Icon has no explicit fill anywhere — inject one on the root svg
        # tag. "0,/<svg/" (GNU sed) matches only the first occurrence in
        # the whole file, not just the first line, same as Python's
        # re.sub(..., count=1) this replaced.
        sed "0,/<svg/{s//<svg fill=\"$accent\"/}" "$src" > "$dst"
    else
        # Space-separated token list (usually just "currentColor") — one
        # -e per token, all applied in a single sed invocation. "|" as
        # delimiter avoids collision with "/" that can appear in SVG path
        # data if a token pattern ever needs to be that specific.
        local sedArgs=()
        for token in $tokens; do
            sedArgs+=(-e "s|$token|$accent|g")
        done
        sed "${sedArgs[@]}" "$src" > "$dst"
    fi
}

# ensure_icon <iconName> — generates the accent-colored SVG in the theme
# dir exactly once per run. Returns 1 if no base SVG exists for the name.
ensure_icon() {
    local name="$1" src
    [ -n "${generatedIcons[$name]:-}" ] && return 0
    src=$(find_base_svg "$name") || return 1
    patch_svg_color "$src" "$iconThemeDir/apps/scalable/$name.svg" "$name"
    generatedIcons[$name]=1
}

cleanup_icon_cache() {
    rm -f "$HOME/.cache/icon-cache.kcache"
    kbuildsycoca6 --noincremental 2>/dev/null
}

# time_step <label> <command...> — runs the given command, prints its
# wall-clock time to stderr afterward. awk instead of bc for the float
# subtraction so this doesn't need an extra package installed. Works for
# both function calls and plain external commands (e.g. the
# TrayIconPatcher.sh invocation and update-desktop-database below).
time_step() {
    local label="$1"; shift
    local start end
    start=$(date +%s.%N)
    "$@"
    end=$(date +%s.%N)
    awk -v s="$start" -v e="$end" -v l="$label" \
        'BEGIN { printf "[TIMING] [%7.3fs] %s\n", e - s, l }' >&2
}

# Same contract as time_step, but backgrounds the command and prefixes
# every line it prints (stdout AND stderr, merged) with "[label] ".
# Output is captured to a temp file rather than piped live through sed —
# see TrayIconPatcher.sh's time_step_bg for why: a live pipe can be held
# open by any backgrounded+disowned grandchild that doesn't redirect its
# own output away first, blocking this whole job from ever finishing even
# though the wrapped command itself already returned. A regular file has
# no such blocking semantics. Never wrap this in $(...) to grab the PID —
# see TrayIconPatcher.sh's time_step_bg for why that reparents the job
# away from this script's job table.
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
            'BEGIN { printf "[TIMING] [%7.3fs] %s\n", e - s, l }' >&2
        exit $rc
    ) &
}

# ---- Run everything, in order ----
if [ "$dryRun" -eq 1 ]; then
    echo "(dry run: dedicated functions are skipped, nothing is written)"
    echo
    patch_all_desktop_icons
    exit 0
fi

# patch_wlogout_icons and patch_osd_icons read only from raw
# $iconsDir/*_base_icon.svg source files and write only to their own
# app-specific config dirs (wlogout/icons, swaync/icons) — they don't
# touch $iconThemeDir, any .desktop file, or handledDesktops/generatedIcons,
# so unlike the dedicated icon functions below (which populate
# handledDesktops for the engine to read — genuinely can't background
# those without breaking that hand-off) these two have no dependency on
# anything else in this script. Launched here so they run for the whole
# rest of the script instead of waiting their turn at the end; waited on
# right before the final "Icons patched" line.
time_step_bg "WlogoutIconPatchers.sh" patch_wlogout_icons
wlogoutPid=$!
time_step_bg "SwayIconsPatcher.sh" patch_osd_icons
osdPid=$!

# Prune stale overrides before anything else scans desktopDirs, so a
# removed entry doesn't shadow a nonexistent original for the rest of
# this run either.
time_step "cleanup_stale_desktop_overrides" cleanup_stale_desktop_overrides

#----------------------------- BreezeIconsPatcher.sh -----------------------------

# Full breeze-dark theme pass first — recolors every accent/highlight icon
# across the whole upstream theme. Dedicated + engine passes below write
# on top of this, so hand-curated app icons still take priority.
time_step "patch_full_breeze_theme" patch_full_breeze_theme

# Dedicated functions next, so the engine knows what's already handled
time_step "patch_folder_icons"             patch_folder_icons
time_step "patch_trash_icon"               patch_trash_icon
time_step "patch_kdeconnect_places_icon"   patch_kdeconnect_places_icon
time_step "patch_inode_directory_icon"     patch_inode_directory_icon
time_step "patch_system_file_manager_icon" patch_system_file_manager_icon
time_step "patch_preferences_system_icon"  patch_preferences_system_icon
time_step "patch_dolphin_icon"             patch_dolphin_icon

#----------------------------- CachyOsIconsPatcher.sh ----------------------------

time_step "patch_cachyos_hello_icon"            patch_cachyos_hello_icon
#time_step "patch_cachyos_kernel_manager_icon"   patch_cachyos_kernel_manager_icon

#---------------------------------------------------------------------------------

time_step "DiscordVesktopIconPatcher.sh"    patch_discord_vesktop_icons
#time_step "NativmixIconPatcher.sh"          patch_nativmix_icon
#time_step "patch_orcaslicer_icon"           patch_orcaslicer_icon
#time_step "ConkyIconPatcher.sh"             patch_conky_icon

# The generic engine — everything else, games included
time_step "DesktopEntriesPatcher.sh" patch_all_desktop_icons

# Tray icons — split into its own file, see TrayIconPatcher.sh
time_step "TrayIconPatcher.sh" "$supportDir/TrayIconPatcher.sh" "$color"

_run_update_desktop_database() {
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
}
time_step "update-desktop-database" _run_update_desktop_database

time_step "cleanup_icon_cache" cleanup_icon_cache

wait "$wlogoutPid" "$osdPid"

echo "Icons patched with $accent"