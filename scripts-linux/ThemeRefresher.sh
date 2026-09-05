#!/usr/bin/env bash
# ThemeRefresher.sh
# Entry point for the whole theming pipeline. Picks an accent color from
# the wallpaper, then fans out to every per-app/per-subsystem patcher
# (RGB, KDE, GTK, browsers, mail, Discord, icons, VS Code, SourceGit,
# ...), restarts the apps it just patched, and restores window layout.
#
# Usage: ThemeRefresher.sh --full|--rgb|--softrun|--tray|--help

supportDir="$HOME/.config/WallpaperChanger/ThemeRefresherSupportScripts"

# Runs "$@", prints its wall-clock time to stderr as "[timing] label: Ns".
# Timing goes to stderr so `color=$(time_step ColorChooser ...)` still only
# captures the wrapped command's real stdout.
time_step() {
    local label="$1"; shift
    local startTime endTime elapsed rc
    startTime=$(date +%s%N)
    "$@"
    rc=$?
    endTime=$(date +%s%N)
    elapsed=$(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
    echo "[timing] ${label}: ${elapsed}s" >&2
    return $rc
}

# Same contract as time_step, but backgrounds "$@" instead of waiting for
# it. Callers fire-and-collect $! themselves; the timing line still prints
# once the job finishes (from inside the subshell).
#
# Every line "$@" prints (stdout+stderr merged) is prefixed "[label] ".
# Output is captured to a temp file rather than piped live through sed:
# a wrapped script that itself backgrounds+disowns work (RgbApply.sh's
# ratbagctl loop does this) inherits this job's stdout/stderr fd. Piped
# through sed, that disowned grandchild would hold the pipe open until IT
# finishes too — even though the wrapped script already returned — so
# `wait` would block on unrelated background work. A regular file has no
# such blocking semantics. Trade-off: output only appears (all at once,
# labeled) once the wrapped command's own script portion finishes.
#
# IMPORTANT: never wrap this in $(...) to grab the PID — command
# substitution runs in its own subshell, so a job backgrounded inside it
# gets reparented away (not a child of this script) once that subshell
# exits, and `wait $pid` from here would silently fail to wait for it.
# Call directly, then read $! right after:
#   time_step_bg "label" some_cmd args...
#   myPids+=("$!")
time_step_bg() {
    local label="$1"; shift
    local outFile
    outFile=$(mktemp)
    (
        local startTime endTime elapsed rc
        startTime=$(date +%s%N)
        "$@" > "$outFile" 2>&1
        rc=$?
        endTime=$(date +%s%N)
        sed "s/^/[$label] /" "$outFile"
        rm -f "$outFile"
        elapsed=$(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
        echo "[timing] ${label}: ${elapsed}s" >&2
        exit $rc
    ) &
}

usage() {
    cat << EOF
Usage: ./install-Linux.sh [OPTION]

Options:
  --full             Run the full theme refresh process (including restarting apps)
  --rgb              Apply the accent color to RGB devices only
  --softrun          Apply the accent color to RGB devices, patch themes and icons, but do not restart any apps
  --tray             Run the tray icon updater only
  --help             Show this help message
EOF
}

# Blocks until a window of each given Hyprland class appears (or the
# shared 5s deadline is hit). Used so HyprLayoutPreservation.sh's restore
# only runs once every relaunched window actually exists — otherwise a
# late-appearing window (e.g. Spotify) grabs focus after restore already
# set it. Every app shares one deadline and is checked every tick, so one
# slow app no longer blocks the ones behind it, and each tick costs one
# `hyprctl clients -j` call total instead of one per app.
#   $1 (nameref) - array of "app|class" entries to wait for
wait_for_hypr_classes() {
    local -n pending="$1"
    local deadline=$(( $(date +%s) + 5 ))
    local startTime=$(date +%s%N)

    while [ ${#pending[@]} -gt 0 ] && [ "$(date +%s)" -lt "$deadline" ]; do
        local clientsJson
        clientsJson=$(hyprctl clients -j)
        local -a stillPending=()
        for entry in "${pending[@]}"; do
            local app="${entry%%|*}"
            local windowClass="${entry#*|}"
            if printf '%s' "$clientsJson" | python3 -c "
import json, sys
clients = json.load(sys.stdin)
sys.exit(0 if any('$windowClass'.lower() in c.get('class', '').lower() for c in clients) else 1)
" 2>/dev/null; then
                local endTime=$(date +%s%N)
                local elapsed=$(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
                echo "[timing] wait_for_hypr_class(${app}): ${elapsed}s" >&2
            else
                stillPending+=("$entry")
            fi
        done
        pending=("${stillPending[@]}")
        [ ${#pending[@]} -gt 0 ] && sleep 0.1
    done

    # Anything left never appeared within the shared deadline — still emit
    # a timing line for it.
    if [ ${#pending[@]} -gt 0 ]; then
        local endTime=$(date +%s%N)
        local elapsed=$(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
        for entry in "${pending[@]}"; do
            echo "[timing] wait_for_hypr_class(${entry%%|*}): ${elapsed}s" >&2
        done
    fi
}

# Group A: patchers that only need the raw hex color, write to a file
# tree none of the others touch, and never read anything matugen renders
# — safe to launch fully concurrently with each other and with matugen.
# Group B: patchers that need matugen's rendered output (IconPatcher and
# VscodePatcher degrade gracefully to the raw seed if it's missing;
# SourceGitPatcher hard-requires it) — wait for matugen, but not Group A.
run_patchers() {
    local color="$1"
    declare -a patcherPids=()

    time_step_bg "RgbApply" "$supportDir/RgbApply.sh" "$color"
    patcherPids+=("$!")
    time_step_bg "KdePatcher" "$supportDir/KdePatcher.sh" "$color"
    patcherPids+=("$!")
    time_step_bg "GtkPatcher" "$supportDir/GtkPatcher.sh" "$color"
    patcherPids+=("$!")
    if command -v ferdium >/dev/null 2>&1; then
        time_step_bg "FerdiumPatcher" "$supportDir/appPatchers/FerdiumPatcher.sh" "$color"
        patcherPids+=("$!")
        time_step_bg "FerdiumIconPatcher" "$supportDir/appPatchers/FerdiumIconPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v vesktop >/dev/null 2>&1; then
        time_step_bg "DiscordPatcher" "$supportDir/appPatchers/DiscordPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v zen-browser >/dev/null 2>&1; then
        time_step_bg "ZenPatcher" "$supportDir/appPatchers/ZenPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v firefox >/dev/null 2>&1; then
        time_step_bg "FirefoxPatcher" "$supportDir/appPatchers/FirefoxPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v betterbird >/dev/null 2>&1 || command -v thunderbird >/dev/null 2>&1; then
        time_step_bg "ThunderbirdPatcher" "$supportDir/appPatchers/ThunderbirdPatcher.sh" "$color"
        patcherPids+=("$!")
    fi

    # matugen, launched alongside Group A — nothing in Group A reads its output.
    time_step_bg "matugen" matugen color hex "#$color" --quiet
    local matugenPid=$!

    wait "$matugenPid"

    time_step_bg "IconPatcher" "$supportDir/IconPatcher.sh" "$color"
    patcherPids+=("$!")
    if command -v code >/dev/null 2>&1; then
        time_step_bg "VscodePatcher" "$supportDir/appPatchers/VscodePatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        time_step_bg "SourceGitPatcher" "$supportDir/appPatchers/SourceGitPatcher.sh" "$color"
        patcherPids+=("$!")
    fi

    for pid in "${patcherPids[@]}"; do
        wait "$pid"
    done
}

cmd_full() {
    # Save Hyprland layout state before any restarts. Backgrounded: it
    # touches neither color nor any theme file, so ColorChooser doesn't
    # need to wait on it — it only needs to finish before AppRestarter
    # runs, much further down, so it gets this whole pipeline's worth of
    # headroom for free. Waited on right before AppRestarter below.
    hyprSavePid=""
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        time_step_bg "HyprLayoutPreservation save" "$supportDir/HyprLayoutPreservation.sh" save
        hyprSavePid=$!
    fi

    # Choosing the color is genuinely serial — every patcher below needs it.
    color=$(time_step "ColorChooser" "$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Every patcher must be fully finished before AppRestarter (below)
    # relaunches the apps they theme — a relaunch racing an in-flight
    # patcher could load a half-written or stale config. Concurrent jobs'
    # own stdout/stderr interleave line-by-line above; accepted tradeoff
    # of running them in parallel.
    run_patchers "$color"

    declare -A apps
    apps[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
    apps[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|ferdium"
    apps[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"
    apps[code]="x|code|code|code|code"
    apps[vesktop]="x|vesktop|vesktop|vesktop -m|"
    apps[nativmix]="x|nativmix|nativmix|nativmix --hidden --restart|"
    apps[localsend]="x|localsend|localsend|localsend --hidden|"
    apps[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird"
    apps[thunderbird]="f|thunderbird|thunderbird|thunderbird|org.mozilla.Thunderbird"
    apps[swaync]="x|swaync|swaync|swaync"

    # HyprLayoutPreservation save (backgrounded above) must finish before
    # AppRestarter starts killing/relaunching windows.
    [ -n "$hyprSavePid" ] && wait "$hyprSavePid"

    # Sourced directly (not via time_step) so $running lands in THIS
    # shell for the wait_for_hypr_classes call below.
    appRestarterStart=$(date +%s%N)
    source "$supportDir/AppRestarter.sh"
    appRestarterEnd=$(date +%s%N)
    echo "[timing] AppRestarter: $(awk -v a="$appRestarterStart" -v b="$appRestarterEnd" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2

    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        declare -a hyprPending=()
        for app in "${running[@]}"; do
            IFS='|' read -r _ _ _ _ windowClass <<< "${apps[$app]}"
            [ -z "$windowClass" ] && continue
            echo "Waiting for $app to appear..."
            hyprPending+=("${app}|${windowClass}")
        done
        [ ${#hyprPending[@]} -gt 0 ] && wait_for_hypr_classes hyprPending
    fi

    # Desktop-environment-specific actions
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        # Restore Hyprland layout state after all restarts (Spotify included)
        time_step "HyprLayoutPreservation restore" "$supportDir/HyprLayoutPreservation.sh" restore
        time_step "waybar restart" systemctl --user restart waybar.service
    elif [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    fi
}

cmd_rgb() {
    color=$("$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    "$supportDir/RgbApply.sh" "$color"
}

cmd_softrun() {
    color=$(time_step "ColorChooser" "$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Wait for every patcher before restarting plasmashell/waybar below —
    # otherwise the restart could happen before some configs are written.
    run_patchers "$color"

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        time_step "waybar restart" systemctl --user restart waybar.service
    fi
}

cmd_tray() {
    color=$(time_step "ColorChooser" "$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    time_step "TrayIconPatcher.sh" "$supportDir/TrayIconPatcher.sh" "$color"

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        time_step "waybar restart" systemctl --user restart waybar.service
    fi
}

case "$1" in
    --full)        cmd_full ;;
    --rgb)         cmd_rgb ;;
    --softrun)     cmd_softrun ;;
    --tray)        cmd_tray ;;
    --help)        usage ;;
    *)
        if [ -z "$1" ]; then
            echo "No option provided."
        else
            echo "Unknown option: $1"
        fi
        echo ""
        usage
        exit 1
        ;;
esac