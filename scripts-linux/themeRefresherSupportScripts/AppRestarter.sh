#!/usr/bin/env bash
# AppRestarter.sh
# Sourced by ThemeRefresher.sh (cmd_full). Restarts apps in two phases so the
# slow part -- waiting for them to exit -- overlaps with the theme patchers
# instead of adding to the end of the run:
#
#   app_stop_begin [name...]  detect running apps (default: every app in $apps)
#                             and start stopping each one in the background
#   app_stop_wait             block until every stop started so far has finished
#   app_start_all             relaunch every app that was stopped, then run the
#                             special-cased restarters (OneDrive, Spicetify)
#
# After app_stop_begin, $running lists the apps that were stopped. It
# accumulates across calls, so a late app_stop_begin (e.g. Sonora, whose
# restart is only known once matugen has rendered) just adds to it.
#
# Needs from the caller: the associative array `apps`, and $supportDir.
# Format: apps[name]="pgrepFlag|detectPattern|killPattern|launchCmd|hyprlandWindowClass|gracePeriod"
# Example:
#   declare -A apps
#   apps[zen]="f|zen-bin|zen-bin|zen-browser|zen"
#   apps[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
#   source AppRestarter.sh
#
# Note: ThemeRefresher.sh must read the class with a trailing `_` so the
# optional 6th (grace) field never ends up inside it:
#   IFS='|' read -r _ _ _ _ windowClass _ <<< "${apps[$app]}"

running=()
stopPids=()

# Default grace period (seconds) between SIGTERM and SIGKILL. Most apps die
# almost instantly, so this rarely gets used in full. Apps that need longer
# (e.g. Betterbird flushing its profile DB before releasing its lock) can
# override it with the optional 6th field; 0 means SIGKILL right away, for apps
# that are going to be force-killed after the full grace anyway:
#   apps[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird|5"
defaultGrace=1

# pgrep by exact process name (flag x) or by full command line (flag f).
_pgrep_app() {
    if [ "$1" = "f" ]; then
        pgrep -f "$2" 2>/dev/null
    else
        pgrep -x "$2" 2>/dev/null
    fi
}

# SIGTERM the given pids, wait up to the app's grace period for them to exit,
# then SIGKILL whatever is left. Runs as its own background job so a slow app
# never delays a fast one.
#   $1 - app name   $2.. - pids to stop
# ${EPOCHREALTIME/,/.} because bash prints the locale's decimal separator
# (a comma in Italian locales), which awk would truncate.
stop_app() {
    local app="$1"; shift
    local -a pids=("$@")
    local grace maxIters i pid allDead forced=0 t0=${EPOCHREALTIME/,/.}

    IFS='|' read -r _ _ _ _ _ grace <<< "${apps[$app]}"
    grace=${grace:-$defaultGrace}
    maxIters=$(( grace * 20 ))   # polled every 0.05s

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
        kill -0 "$pid" 2>/dev/null && { kill -9 "$pid" 2>/dev/null; forced=1; }
    done

    echo "[timing] stop($app): $(awk -v a="$t0" -v b="${EPOCHREALTIME/,/.}" 'BEGIN{printf "%.3f", b-a}')s$([ "$forced" -eq 1 ] && echo ' (hit grace, SIGKILL)')" >&2
}

# Detect which of the given apps (default: all in $apps) are running and start
# stopping them. Detection runs here, in the caller's shell, so $running and
# $stopPids are set for the caller; only the waiting happens in the background.
app_stop_begin() {
    local app flag detectPattern
    local -a candidates=("$@") pids
    [ ${#candidates[@]} -eq 0 ] && candidates=("${!apps[@]}")

    for app in "${candidates[@]}"; do
        [ -n "${apps[$app]:-}" ] || continue
        IFS='|' read -r flag detectPattern _ <<< "${apps[$app]}"
        mapfile -t pids < <(_pgrep_app "$flag" "$detectPattern")
        [ ${#pids[@]} -gt 0 ] || continue

        echo "$app running"
        running+=("$app")
        stop_app "$app" "${pids[@]}" &
        stopPids+=("$!")
    done
}

# Wait for every stop started by app_stop_begin.
app_stop_wait() {
    [ ${#stopPids[@]} -gt 0 ] && wait "${stopPids[@]}"
    stopPids=()
}

# Relaunch every app that was stopped, then the special cases below.
app_start_all() {
    local app launchCmd

    for app in "${running[@]}"; do
        IFS='|' read -r _ _ _ launchCmd _ <<< "${apps[$app]}"
        $launchCmd >/dev/null 2>&1 &
        disown
    done

    # Special-cased: killing only the GUI orphans its `onedrive --monitor`
    # child, which keeps the lock file and blocks a plain relaunch.
    if command -v onedrivegui >/dev/null 2>&1 && pgrep -f "onedrivegui" >/dev/null 2>&1; then
        "$supportDir/appPatchers/OneDriveRestarter.sh"
    fi

    # Special-cased: spicetify refuses to patch a running Spotify, so it must
    # close, apply, then reopen. Runs before HyprLayoutPreservation restore so
    # its window doesn't steal focus after restore.
    if command -v spicetify >/dev/null 2>&1; then
        "$supportDir/appPatchers/SpicetifyRestarter.sh"
    fi
}