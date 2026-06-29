#!/usr/bin/env bash
# hyprMasterLayoutPreservation.sh
# Saves and restores Hyprland master layout state for ALL tiled workspaces.
#
# Usage:
#   hyprMasterLayoutPreservation.sh save
#   hyprMasterLayoutPreservation.sh restore

STATE_FILE="/tmp/hyprLayoutState.txt"

# Classes that should never be moved between workspaces during restore
# (e.g. terminal emulators that may have multiple instances)
NEVER_MOVE_CLASSES="kitty"

save_layout() {
    local current_ws
    current_ws=$(hyprctl activeworkspace -j | jq '.id')
    echo "Current workspace: $current_ws"

    {
        echo "current_workspace:$current_ws"

        hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)

workspaces = {}
for c in clients:
    ws_id = c['workspace']['id']
    if ws_id <= 0:
        continue
    if ws_id not in workspaces:
        workspaces[ws_id] = []
    workspaces[ws_id].append(c)

for ws_id, ws_clients in sorted(workspaces.items()):
    if len(ws_clients) == 1:
        c = ws_clients[0]
        print('workspace:' + str(ws_id))
        print('master:' + c['address'] + ':' + c['class'])
        print('---')
        continue

    master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
    slaves = [c for c in ws_clients if c['address'] != master['address']]
    print('workspace:' + str(ws_id))
    print('master:' + master['address'] + ':' + master['class'])
    for c in sorted(slaves, key=lambda x: (x['at'][1], x['at'][0])):
        print('slave:' + c['address'] + ':' + c['class'])
    print('---')
"
    } > "$STATE_FILE"

    if [ -s "$STATE_FILE" ]; then
        echo "Layout saved for workspaces:"
        grep "^workspace:" "$STATE_FILE" | cut -d: -f2
    else
        echo "No layouts found to save"
        rm -f "$STATE_FILE"
    fi
}

# Check if a class is in the never-move list
is_never_move() {
    local class="$1"
    echo "$NEVER_MOVE_CLASSES" | tr ',' '\n' | grep -qi "^${class}$"
}

restore_layout() {
    if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        echo "No saved layout state found, skipping restore"
        return
    fi

    local saved_workspace
    saved_workspace=$(grep "^current_workspace:" "$STATE_FILE" | cut -d: -f2)
    echo "Will return to workspace: $saved_workspace"

    restore_workspace() {
        local ws_id="$1"
        local m_class="$2"
        local -n o_classes="$3"

        echo "Restoring workspace $ws_id (master: $m_class)"

        # Single window workspace — move it silently (skip if never-move class)
        if [ ${#o_classes[@]} -eq 0 ]; then
            if ! is_never_move "$m_class"; then
                hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"class:$m_class\", silent = true })" 2>/dev/null
            fi
            return
        fi

        # Move slaves to correct workspace (skip never-move classes)
        for slave_class in "${o_classes[@]}"; do
            if is_never_move "$slave_class"; then
                echo "  Skipping move for $slave_class (never-move class)"
                continue
            fi
            local slv_ws
            slv_ws=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
for c in clients:
    if '$slave_class'.lower() in c.get('class','').lower():
        print(c['workspace']['id'])
        break
" 2>/dev/null)
            if [ -n "$slv_ws" ] && [ "$slv_ws" != "$ws_id" ]; then
                echo "  Moving $slave_class from ws $slv_ws to ws $ws_id"
                hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"class:$slave_class\", silent = true })" 2>/dev/null
                sleep 0.2
            fi
        done

        # Move master to correct workspace (skip if never-move class)
        if ! is_never_move "$m_class"; then
            local mstr_ws
            mstr_ws=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
for c in clients:
    if '$m_class'.lower() in c.get('class','').lower():
        print(c['workspace']['id'])
        break
" 2>/dev/null)
            if [ -n "$mstr_ws" ] && [ "$mstr_ws" != "$ws_id" ]; then
                echo "  Moving master $m_class from ws $mstr_ws to ws $ws_id"
                hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"class:$m_class\", silent = true })" 2>/dev/null
                sleep 0.2
            fi
        fi

        # Step 1: set correct master only if needed
        local cur_master
        cur_master=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $ws_id]
if not ws_clients:
    exit(1)
master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
print(master['class'])
" 2>/dev/null)

        if [ -n "$cur_master" ] && ! echo "$cur_master" | grep -qi "^${m_class}$"; then
            echo "  Promoting $m_class to master on ws $ws_id"
            hyprctl dispatch "hl.dsp.focus({ window = \"class:$m_class\", silent = true })" 2>/dev/null
            sleep 0.3
            hyprctl dispatch 'hl.dsp.layout("swapwithmaster master")'
            sleep 0.3
        fi

        # Step 2: restore each slave slot in order
        for target_slot in "${!o_classes[@]}"; do
            local target_class="${o_classes[$target_slot]}"

            local cur_slot
            cur_slot=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $ws_id]
if not ws_clients:
    exit(1)
master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
slaves = [c for c in ws_clients if c['address'] != master['address']]
for i, c in enumerate(sorted(slaves, key=lambda x: (x['at'][1], x['at'][0]))):
    if '$target_class'.lower() in c['class'].lower():
        print(i)
        break
" 2>/dev/null)

            if [ -n "$cur_slot" ] && [ "$cur_slot" -gt 0 ]; then
                local n_swaps=$(( cur_slot - target_slot ))
                if [ $n_swaps -gt 0 ]; then
                    echo "  Moving $target_class from slot $cur_slot to slot $target_slot"
                    hyprctl dispatch "hl.dsp.focus({ window = \"class:$target_class\", silent = true })" 2>/dev/null
                    sleep 0.2
                    for i in $(seq 1 $n_swaps); do
                        hyprctl dispatch 'hl.dsp.layout("swapprev")'
                        sleep 0.2
                    done
                fi
            fi
        done
    }

    # Read state file and restore each workspace
    local loop_ws=""
    local loop_master=""
    declare -a loop_slaves

    while IFS= read -r line; do
        if [[ "$line" == current_workspace:* ]]; then
            continue
        elif [[ "$line" == workspace:* ]]; then
            loop_ws="${line#workspace:}"
            loop_master=""
            loop_slaves=()
        elif [[ "$line" == master:* ]]; then
            loop_master=$(echo "$line" | cut -d: -f3)
        elif [[ "$line" == slave:* ]]; then
            loop_slaves+=("$(echo "$line" | cut -d: -f3)")
        elif [[ "$line" == "---" ]]; then
            if [ -n "$loop_ws" ] && [ -n "$loop_master" ]; then
                restore_workspace "$loop_ws" "$loop_master" loop_slaves
            fi
            loop_ws=""
            loop_master=""
            loop_slaves=()
        fi
    done < "$STATE_FILE"

    # Return to original workspace — retry until it sticks
    for i in $(seq 1 5); do
        sleep 0.3
        hyprctl dispatch "hl.dsp.focus({ workspace = $saved_workspace })"
        current=$(hyprctl activeworkspace -j | jq '.id')
        [ "$current" = "$saved_workspace" ] && break
    done

    rm -f "$STATE_FILE"
    echo "Layout restore complete"
}

case "$1" in
    save)    save_layout ;;
    restore) restore_layout ;;
    *)
        echo "Usage: $0 save|restore"
        exit 1
        ;;
esac