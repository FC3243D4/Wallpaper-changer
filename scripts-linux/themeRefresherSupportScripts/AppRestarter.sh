#!/usr/bin/env bash
# AppRestarter.sh
# Restarts a set of apps defined in an associative array (named `apps`)
# supplied by the caller via `source AppRestarter.sh`.
# Format: apps[name]="pgrepFlag|detectPattern|killPattern|launchCmd|hyprlandWindowClass|gracePeriod"
# Example:
#   declare -A apps
#   apps[zen]="f|zen-bin|zen-bin|zen-browser|zen"
#   apps[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
#   source AppRestarter.sh

running=()
allPids=()

for app in "${!apps[@]}"; do
    IFS='|' read -r flag detectPattern _ _ _ <<< "${apps[$app]}"
    if [ "$flag" = "f" ]; then
        mapfile -t appPids < <(pgrep -f "$detectPattern" 2>/dev/null)
    else
        mapfile -t appPids < <(pgrep -x "$detectPattern" 2>/dev/null)
    fi
    if [ ${#appPids[@]} -gt 0 ]; then
        echo "$app running"
        running+=("$app")
        allPids+=("${appPids[@]}")
    fi
done

# Default grace period (seconds) between SIGTERM and SIGKILL. Most apps
# die almost instantly, so this rarely gets used in full. Apps that need
# longer (e.g. Betterbird flushing its profile DB before releasing its
# lock) can override it via an optional 6th "|grace" field:
#   apps[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird|5"
defaultGrace=1

# Kill, wait, and relaunch a single app. Runs as its own background job so
# a slow-to-die app never delays a fast one's relaunch — e.g. nativmix
# used to sit waiting on Betterbird's grace period before it was allowed
# to restart, which meant it came back up after PipeWire's sink state had
# already settled elsewhere, missing the current volume until a slider
# was touched to force a resync.
restart_app() {
    local app="$1"
    local flag detectPattern launchCmd grace pids pid i maxIters allDead
    IFS='|' read -r flag detectPattern _ launchCmd _ grace <<< "${apps[$app]}"
    grace=${grace:-$defaultGrace}
    maxIters=$(( grace * 20 ))  # polled every 0.05s

    if [ "$flag" = "f" ]; then
        mapfile -t pids < <(pgrep -f "$detectPattern" 2>/dev/null)
    else
        mapfile -t pids < <(pgrep -x "$detectPattern" 2>/dev/null)
    fi
    [ ${#pids[@]} -eq 0 ] && return

    kill "${pids[@]}" 2>/dev/null

    i=0
    while [ $i -lt $maxIters ]; do
        allDead=1
        for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && allDead=0 && break
        done
        [ $allDead -eq 1 ] && break
        sleep 0.05
        i=$((i + 1))
    done

    for pid in "${pids[@]}"; do
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    done

    $launchCmd >/dev/null 2>&1 &
    disown
}

for app in "${!apps[@]}"; do
    IFS='|' read -r flag detectPattern _ _ _ <<< "${apps[$app]}"
    if [ "$flag" = "f" ]; then
        found=$(pgrep -f "$detectPattern" 2>/dev/null)
    else
        found=$(pgrep -x "$detectPattern" 2>/dev/null)
    fi
    if [ -n "$found" ]; then
        echo "$app running"
        restart_app "$app" &
    fi
done

# Wait for every app's kill/relaunch job to finish before the special
# cases below, which assume the main restart pass is done.
wait

# Special-cased: killing only the GUI orphans its `onedrive --monitor`
# child, which keeps the lock file and blocks a plain relaunch.
if command -v onedrivegui >/dev/null 2>&1 && pgrep -f "onedrivegui" >/dev/null 2>&1; then
    "$supportDir/appPatchers/OneDriveRestarter.sh"
fi

# Special-cased: spicetify refuses to patch a running Spotify, so it must
# close, apply, then reopen. Runs before HyprLayoutPreservation restore
# (below) so its window doesn't steal focus after restore.
if command -v spicetify >/dev/null 2>&1; then
    "$supportDir/appPatchers/SpicetifyRestarter.sh"
fi