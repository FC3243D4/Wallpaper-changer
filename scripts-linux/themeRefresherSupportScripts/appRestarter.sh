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

running=()
all_pids=()

for app in "${!APPS[@]}"; do
    IFS='|' read -r flag detect _ _ _ <<< "${APPS[$app]}"
    if [ "$flag" = "f" ]; then
        mapfile -t apids < <(pgrep -f "$detect" 2>/dev/null)
    else
        mapfile -t apids < <(pgrep -x "$detect" 2>/dev/null)
    fi
    if [ ${#apids[@]} -gt 0 ]; then
        echo "$app running"
        running+=("$app")
        all_pids+=("${apids[@]}")
    fi
done

# Kill all PIDs in one syscall
[ ${#all_pids[@]} -gt 0 ] && kill "${all_pids[@]}" 2>/dev/null

# Wait briefly then force kill anything still alive
sleep 0.5
for pid in "${all_pids[@]}"; do
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
done

# Wait for all to die using kill -0 (fast polling)
if [ ${#all_pids[@]} -gt 0 ]; then
    deadline=$(( $(date +%s) + 5 ))
    while [ $(date +%s) -lt $deadline ]; do
        all_dead=1
        for pid in "${all_pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && all_dead=0 && break
        done
        [ $all_dead -eq 1 ] && break
        sleep 0.05
    done
fi

# Launch all at once
for app in "${running[@]}"; do
    IFS='|' read -r _ _ _ launch _ <<< "${APPS[$app]}"
    $launch >/dev/null 2>&1 &
    disown
done

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
