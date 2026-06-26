#!/usr/bin/env bash
# hyprMasterLayoutPreservation.sh
# Saves and restores Hyprland master layout state for ALL tiled workspaces.
#
# Usage:
#   hyprMasterLayoutPreservation.sh save
#   hyprMasterLayoutPreservation.sh restore
#
# Place save at the very start of your script (before any restarts),
# and restore at the very end (after all apps have relaunched).

STATE_FILE="/tmp/hyprLayoutState.txt"

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
    # Skip workspaces with only one window (nothing to preserve)
    if len(ws_clients) < 2:
        continue
    # Master is the window with largest area
    master = max(ws_clients, key=lambda x: x['size'][0] * x['size'][1])
    slaves = [c for c in ws_clients if c['address'] != master['address']]
    # Only save if it looks like a master layout (master is notably larger)
    master_area = master['size'][0] * master['size'][1]
    slave_areas = [c['size'][0] * c['size'][1] for c in slaves]
    if not slave_areas or master_area <= max(slave_areas):
        continue
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
        echo "No master layouts found to save"
        rm -f "$STATE_FILE"
    fi
}

restore_layout() {
    if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        echo "No saved layout state found, skipping restore"
        return
    fi

    # Parse state file into per-workspace blocks
    current_ws=""
    master_class=""
    declare -a original_classes

    restore_workspace() {
        local ws_id="$1"
        local m_class="$2"
        local -n o_classes="$3"

        if [ ${#o_classes[@]} -eq 0 ]; then
            return
        fi

        echo "Restoring workspace $ws_id (master: $m_class, slaves: ${o_classes[*]})"

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
            # End of workspace block — restore it
            if [ -n "$current_ws" ] && [ -n "$master_class" ]; then
                restore_workspace "$current_ws" "$master_class" original_classes
            fi
            current_ws=""
            master_class=""
            original_classes=()
        fi
    done < "$STATE_FILE"

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