#!/usr/bin/env bash
# SpicetifyRestarter.sh
# Special-cased instead of going through AppRestarter.sh's generic
# mechanism: spicetify refuses to patch a running Spotify, so it must
# close, apply, then reopen. Called from ThemeRefresher.sh before
# HyprLayoutPreservation.sh's restore, so Spotify's window doesn't steal
# focus after restore.

# Standalone copy of ThemeRefresher.sh's wait_for_hypr_class — kept local
# so this script has no dependency on the caller's shell functions.
wait_for_hypr_class() {
    local windowClass="$1"
    local deadline=$(( $(date +%s) + 5 ))
    while [ $(date +%s) -lt $deadline ]; do
        hyprctl clients -j | python3 -c "
import json,sys
clients=json.load(sys.stdin)
exit(0 if any('$windowClass' in c.get('class','').lower() for c in clients) else 1)
" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

startTime=$(date +%s%N)
spotifyWasRunning=false

if pgrep -x spotify >/dev/null 2>&1; then
    spotifyWasRunning=true
    killStartTime=$(date +%s%N)

    echo "Closing Spotify to apply theme..."
    pkill -x spotify
    # Brief grace period for a clean exit, then force it — Spotify has
    # nothing critical to lose, unlike waiting out a slow quit.
    for _ in $(seq 1 6); do
        pgrep -x spotify >/dev/null 2>&1 || break
        sleep 0.05
    done
    if pgrep -x spotify >/dev/null 2>&1; then
        pkill -9 -x spotify
        while pgrep -x spotify >/dev/null 2>&1; do
            sleep 0.05
        done
    fi

    killEndTime=$(date +%s%N)
    echo "[timing]   spotify kill+wait-for-death: $(awk -v a="$killStartTime" -v b="$killEndTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2
fi

echo "Applying Spicetify theme..."
applyStartTime=$(date +%s%N)
spicetify apply >/dev/null 2>&1
applyEndTime=$(date +%s%N)
echo "[timing]   spicetify apply: $(awk -v a="$applyStartTime" -v b="$applyEndTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2

if [ "$spotifyWasRunning" = true ]; then
    echo "Reopening Spotify..."
    relaunchStartTime=$(date +%s%N)
    spotify >/dev/null 2>&1 &
    disown
    [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ] && wait_for_hypr_class "spotify"
    relaunchEndTime=$(date +%s%N)
    echo "[timing]   spotify relaunch+wait-for-window: $(awk -v a="$relaunchStartTime" -v b="$relaunchEndTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2
fi

endTime=$(date +%s%N)
echo "[timing] spicetify/spotify: $(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2