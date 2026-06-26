#!/usr/bin/env bash
# hyprMasterLayoutPreservation.sh
# Saves and restores the master layout state around a process restart.
#
# Usage:
#   hyprMasterLayoutPreservation.sh save <app_class>
#   hyprMasterLayoutPreservation.sh restore <app_class>
#
# Example in themeRefresher.sh:
#   hyprMasterLayoutPreservation.sh save zen
#   pkill -f zen-bin && zen-browser &
#   hyprMasterLayoutPreservation.sh restore zen

STATE_FILE="/tmp/hyprLayoutState.txt"
APP_CLASS="${2:-zen}"

save_layout() {
    hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
# Find workspace of the target app
app_ws = next((c['workspace']['id'] for c in clients
               if '$APP_CLASS'.lower() in c.get('class','').lower()), None)
if app_ws is None:
    exit(1)
print(app_ws)
ws_clients = [c for c in clients if c['workspace']['id'] == app_ws]
master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
print('master:' + master['address'] + ':' + master['class'])
slaves = [c for c in ws_clients if c['address'] != master['address']]
for c in sorted(slaves, key=lambda x: (x['at'][1], x['at'][0])):
    print('slave:' + c['address'] + ':' + c['class'])
" > "$STATE_FILE"

    if [ $? -eq 0 ]; then
        echo "Layout saved to $STATE_FILE"
    else
        echo "No window with class '$APP_CLASS' found, skipping layout save"
        rm -f "$STATE_FILE"
    fi
}

restore_layout() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "No saved layout state found, skipping restore"
        return
    fi

    zen_workspace=$(head -1 "$STATE_FILE")
    master_class=$(grep "^master:" "$STATE_FILE" | cut -d: -f3)

    # Build original slave class order
    original_classes=()
    while IFS= read -r line; do
        original_classes+=("$(echo "$line" | cut -d: -f3)")
    done < <(grep "^slave:" "$STATE_FILE")

    # Wait for app window to appear (max 5 seconds)
    echo "Waiting for $APP_CLASS to appear..."
    for i in $(seq 1 10); do
        sleep 0.5
        hyprctl clients -j | python3 -c "
import json,sys
clients=json.load(sys.stdin)
exit(0 if any('$APP_CLASS'.lower() in c.get('class','').lower() for c in clients) else 1)" && break
    done
    sleep 0.3

    # Step 1: set correct master only if needed
    current_master=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $zen_workspace]
if not ws_clients:
    exit(1)
master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
print(master['class'])
")

    if ! echo "$current_master" | grep -qi "^${master_class}$"; then
        echo "Promoting $master_class to master..."
        hyprctl dispatch "hl.dsp.focus({ window = \"class:$master_class\" })"
        sleep 0.3
        hyprctl dispatch 'hl.dsp.layout("swapwithmaster master")'
        sleep 0.3
    else
        echo "$master_class is already master"
    fi

    # Step 2: restore each slave slot in order
    get_current_slave_slot() {
        local target_class="$1"
        hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $zen_workspace]
if not ws_clients:
    exit(1)
master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
slaves = [c for c in ws_clients if c['address'] != master['address']]
for i, c in enumerate(sorted(slaves, key=lambda x: (x['at'][1], x['at'][0]))):
    if '$target_class'.lower() in c['class'].lower():
        print(i)
        break
"
    }

    for target_slot in "${!original_classes[@]}"; do
        target_class="${original_classes[$target_slot]}"
        current_slot=$(get_current_slave_slot "$target_class")

        if [ -n "$current_slot" ] && [ "$current_slot" -gt 0 ]; then
            n_swaps=$(( current_slot - target_slot ))
            if [ $n_swaps -gt 0 ]; then
                echo "Moving $target_class from slot $current_slot to slot $target_slot ($n_swaps swaps)"
                hyprctl dispatch "hl.dsp.focus({ window = \"class:$target_class\" })"
                sleep 0.2
                for i in $(seq 1 $n_swaps); do
                    hyprctl dispatch 'hl.dsp.layout("swapprev")'
                    sleep 0.2
                done
            fi
        fi
    done

    rm -f "$STATE_FILE"
    echo "Layout restored"
}

case "$1" in
    save)    save_layout ;;
    restore) restore_layout ;;
    *)
        echo "Usage: $0 save|restore <app_class>"
        exit 1
        ;;
esac
