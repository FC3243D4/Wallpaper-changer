#!/usr/bin/env bash

# Special-cased instead of going through the generic appRestarter.sh
# mechanism: spicetify refuses to patch a running Spotify, so it must
# close, apply, then reopen. Called from themeRefresher.sh before
# hyprLayoutPreservation.sh restore so Spotify's window doesn't steal
# focus after restore.

# Standalone copy of themeRefresher.sh's wait_for_hypr_class — kept local
# so this script has no dependency on the caller's shell functions.
wait_for_hypr_class() {
    local wclass="$1"
    local deadline=$(( $(date +%s) + 5 ))
    while [ $(date +%s) -lt $deadline ]; do
        hyprctl clients -j | python3 -c "
import json,sys
clients=json.load(sys.stdin)
exit(0 if any('$wclass' in c.get('class','').lower() for c in clients) else 1)
" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}

_t0=$(date +%s%N)
spotify_was_running=false

if pgrep -x spotify >/dev/null 2>&1; then
    spotify_was_running=true
    _kt0=$(date +%s%N)

    echo "Closing Spotify to apply theme..."
    pkill -x spotify
    # Brief grace period for a clean exit, then force it — Spotify
    # has nothing critical to lose, unlike waiting out a slow quit.
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

    _kt1=$(date +%s%N)
    echo "[timing]   spotify kill+wait-for-death: $(awk -v a="$_kt0" -v b="$_kt1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2
fi

echo "Applying Spicetify theme..."
_at0=$(date +%s%N)
spicetify apply >/dev/null 2>&1
_at1=$(date +%s%N)
echo "[timing]   spicetify apply: $(awk -v a="$_at0" -v b="$_at1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2

if [ "$spotify_was_running" = true ]; then
    echo "Reopening Spotify..."
    _rt0=$(date +%s%N)
    spotify >/dev/null 2>&1 &
    disown
    [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ] && wait_for_hypr_class "spotify"
    _rt1=$(date +%s%N)
    echo "[timing]   spotify relaunch+wait-for-window: $(awk -v a="$_rt0" -v b="$_rt1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2
fi

_t1=$(date +%s%N)
echo "[timing] spicetify/spotify: $(awk -v a="$_t0" -v b="$_t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2