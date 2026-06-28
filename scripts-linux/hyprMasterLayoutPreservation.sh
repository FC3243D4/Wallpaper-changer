#!/usr/bin/env bash
# hyprMasterLayoutPreservation.sh
# Saves and restores Hyprland master layout state for ALL tiled workspaces.
#
# Usage:
#   hyprMasterLayoutPreservation.sh save
#   hyprMasterLayoutPreservation.sh restore

STATE_FILE="/tmp/hyprLayoutState.txt"
CURRENT_WORKSPACE=$(hyprctl activeworkspace -j | jq '.id' )

save_layout() {
    hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)

# Group clients by workspace, skip special/scratchpad workspaces (id <= 0)
workspaces = {}
for c in clients:
    ws_id = c['workspace']['id']
    if ws_id <= 0:
        continue
    if ws_id not in workspaces:
        workspaces[ws_id] = []
    workspaces[ws_id].append(c)

for ws_id, ws_clients in sorted(workspaces.items()):
    # Single window — save workspace assignment only
    if len(ws_clients) == 1:
        c = ws_clients[0]
        print('workspace:' + str(ws_id))
        print('master:' + c['address'] + ':' + c['class'])
        print('---')
        continue

    # Multiple windows — save master/slave order
    master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
    slaves = [c for c in ws_clients if c['address'] != master['address']]
    print('workspace:' + str(ws_id))
    print('master:' + master['address'] + ':' + master['class'])
    for c in sorted(slaves, key=lambda x: (x['at'][1], x['at'][0])):
        print('slave:' + c['address'] + ':' + c['class'])
    print('---')
" > "$STATE_FILE"

    if [ -s "$STATE_FILE" ]; then
        echo "Layout saved for workspaces:"
        grep "^workspace:" "$STATE_FILE" | cut -d: -f2
    else
        echo "No layouts found to save"
        rm -f "$STATE_FILE"
    fi
}

restore_layout() {
    if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        echo "No saved layout state found, skipping restore"
        return
    fi

    restore_workspace() {
        local ws_id="$1"
        local m_class="$2"
        local -n o_classes="$3"

        echo "Restoring workspace $ws_id (master: $m_class)"

        # Single window workspace — move it to the correct workspace
        if [ ${#o_classes[@]} -eq 0 ]; then
            hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"class:$m_class\" })" 2>/dev/null
            return
        fi

        # Multi-window: first ensure all slaves are on the correct workspace
        for slave_class in "${o_classes[@]}"; do
            current_ws=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
for c in clients:
    if '$slave_class'.lower() in c.get('class','').lower():
        print(c['workspace']['id'])
        break
" 2>/dev/null)
            if [ -n "$current_ws" ] && [ "$current_ws" != "$ws_id" ]; then
                echo "  Moving $slave_class from ws $current_ws to ws $ws_id"
                hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"class:$slave_class\" })" 2>/dev/null
                sleep 0.2
            fi
        done

        # Ensure master is on correct workspace too
        master_ws=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
for c in clients:
    if '$m_class'.lower() in c.get('class','').lower():
        print(c['workspace']['id'])
        break
" 2>/dev/null)
        if [ -n "$master_ws" ] && [ "$master_ws" != "$ws_id" ]; then
            echo "  Moving master $m_class from ws $master_ws to ws $ws_id"
            hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"class:$m_class\" })" 2>/dev/null
            sleep 0.2
        fi

        # Step 1: set correct master only if needed
        current_master=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $ws_id]
if not ws_clients:
    exit(1)
master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
print(master['class'])
" 2>/dev/null)

        if [ -n "$current_master" ] && ! echo "$current_master" | grep -qi "^${m_class}$"; then
            echo "  Promoting $m_class to master on ws $ws_id"
            hyprctl dispatch "hl.dsp.focus({ window = \"class:$m_class\" })"
            sleep 0.3
            hyprctl dispatch 'hl.dsp.layout("swapwithmaster master")'
            sleep 0.3
        fi

        # Step 2: restore each slave slot in order
        for target_slot in "${!o_classes[@]}"; do
            target_class="${o_classes[$target_slot]}"

            current_slot=$(hyprctl clients -j | python3 -c "
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

            if [ -n "$current_slot" ] && [ "$current_slot" -gt 0 ]; then
                n_swaps=$(( current_slot - target_slot ))
                if [ $n_swaps -gt 0 ]; then
                    echo "  Moving $target_class from slot $current_slot to slot $target_slot"
                    hyprctl dispatch "hl.dsp.focus({ window = \"class:$target_class\" })"
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
    current_ws=""
    master_class=""
    declare -a original_classes

    while IFS= read -r line; do
        if [[ "$line" == workspace:* ]]; then
            current_ws="${line#workspace:}"
            master_class=""
            original_classes=()
        elif [[ "$line" == master:* ]]; then
            master_class=$(echo "$line" | cut -d: -f3)
        elif [[ "$line" == slave:* ]]; then
            original_classes+=("$(echo "$line" | cut -d: -f3)")
        elif [[ "$line" == "---" ]]; then
            if [ -n "$current_ws" ] && [ -n "$master_class" ]; then
                restore_workspace "$current_ws" "$master_class" original_classes
            fi
            current_ws=""
            master_class=""
            original_classes=()
        fi
    done < "$STATE_FILE"

    hyprctl dispatch "hl.dsp.focus({ workspace = $CURRENT_WORKSPACE })"

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