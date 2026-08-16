#!/usr/bin/env bash
# appRestarter.sh
# Restarts a set of apps defined as an associative array passed via environment.
# Usage: source appRestarter.sh after defining APPS array
# Format: APPS[name]="pgrep_flag|detect_pattern|kill_pattern|launch_cmd|hyprland_window_class"
# Example:
#   declare -A APPS
#   APPS[zen]="f|zen-bin|zen-bin|zen-browser|zen"
#   APPS[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
#   source appRestarter.sh

# Default grace period (seconds) between SIGTERM and SIGKILL. Most apps
# die almost instantly, so this rarely gets used in full. Apps that need
# longer (e.g. betterbird flushing its profile DB before releasing its
# lock) can override it via an optional 6th "|grace" field:
#   APPS[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird|5"
DEFAULT_GRACE=1

# Kill, wait, and relaunch a single app. Runs as its own background job
# so a slow-to-die app never delays the relaunch of a fast one - e.g.
# nativmix used to sit waiting on betterbird's grace period before it
# was allowed to restart, which meant it came back up after PipeWire's
# sink state had already settled elsewhere, missing the current volume
# until a slider was touched to force a resync.
restart_app() {
    local app="$1"
    local flag detect launch grace pids pid i max_iters all_dead
    IFS='|' read -r flag detect _ launch _ grace <<< "${APPS[$app]}"
    grace=${grace:-$DEFAULT_GRACE}
    max_iters=$(( grace * 20 ))  # polled every 0.05s

    if [ "$flag" = "f" ]; then
        mapfile -t pids < <(pgrep -f "$detect" 2>/dev/null)
    else
        mapfile -t pids < <(pgrep -x "$detect" 2>/dev/null)
    fi
    [ ${#pids[@]} -eq 0 ] && return

    kill "${pids[@]}" 2>/dev/null

    i=0
    while [ $i -lt $max_iters ]; do
        all_dead=1
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && all_dead=0 && break
        done
        [ $all_dead -eq 1 ] && break
        sleep 0.05
        i=$((i + 1))
    done

    for pid in "${pids[@]}"; do
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    done

    $launch >/dev/null 2>&1 &
    disown
}

for app in "${!APPS[@]}"; do
    IFS='|' read -r flag detect _ _ _ <<< "${APPS[$app]}"
    if [ "$flag" = "f" ]; then
        found=$(pgrep -f "$detect" 2>/dev/null)
    else
        found=$(pgrep -x "$detect" 2>/dev/null)
    fi
    if [ -n "$found" ]; then
        echo "$app running"
        restart_app "$app" &
    fi
done

# Wait for every app's kill/relaunch job to finish before running the
# special cases below, which assume the main restart pass is done.
wait

# Special-cased: killing only the GUI orphans its onedrive --monitor
# child, which keeps the lock file and blocks a plain relaunch.
if command -v onedrivegui >/dev/null 2>&1 && pgrep -f "onedrivegui" >/dev/null 2>&1; then
    "$SUPPORT/appPatchers/oneDriveRestarter.sh"
fi

# Special-cased: spicetify refuses to patch a running Spotify, so it
# must close, apply, then reopen. Runs before hyprLayoutPreservation
# restore (below) so its window doesn't steal focus after restore.
if command -v spicetify >/dev/null 2>&1; then
    "$SUPPORT/appPatchers/spicetifyRestarter.sh"
fi