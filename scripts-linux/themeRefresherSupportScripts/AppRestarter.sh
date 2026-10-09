#!/usr/bin/env bash
# AppRestarter.sh - Split kill/relaunch with robust VS Code handling

defaultGrace=1

if [ "$APPRESTARTER_MODE" = "kill" ] || [ -z "$APPRESTARTER_MODE" ]; then
    running=()
    for app in "${!apps[@]}"; do
        IFS='|' read -r flag detectPattern _ _ _ <<< "${apps[$app]}"
        if [ "$flag" = "f" ]; then
            mapfile -t appPids < <(pgrep -f "$detectPattern" 2>/dev/null)
        else
            mapfile -t appPids < <(pgrep -x "$detectPattern" 2>/dev/null)
        fi
        if [ ${#appPids[@]} -gt 0 ]; then
            echo "$app running, terminating..."
            running+=("$app")
            kill "${appPids[@]}" 2>/dev/null
        fi
    done
    export SAVED_RUNNING="${running[*]}"
fi

[ "$APPRESTARTER_MODE" = "kill" ] && return 0

running=(${SAVED_RUNNING:-})

restart_app_launch() {
    local app="$1"
    local flag detectPattern launchCmd grace
    IFS='|' read -r flag detectPattern _ launchCmd _ grace <<< "${apps[$app]}"
    
    # Give disk/processes a micro-moment to release file locks (especially for Electron apps like VS Code)
    sleep 0.2
    
    # Explicitly check for VS Code to ensure safe spawning
    if [ "$app" = "code" ]; then
        nohup code >/dev/null 2>&1 &
        disown
    else
        $launchCmd >/dev/null 2>&1 &
        disown
    fi
    echo "[timing] relaunch($app)" >&2
}

for app in "${running[@]}"; do
    restart_app_launch "$app" &
done
wait

if command -v onedrivegui >/dev/null 2>&1; then
    onedrivegui >/dev/null 2>&1 &
    disown
fi

if command -v spicetify >/dev/null 2>&1; then
    spicetify apply >/dev/null 2>&1
    spotify >/dev/null 2>&1 &
    disown
fi