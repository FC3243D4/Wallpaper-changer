#!/usr/bin/env bash

# Restores a single master-layout workspace: places the saved master and
# slaves on the right workspace, promotes the correct window to master,
# then bubble-sorts each slave into its saved slot via swapprev.
#   wsId          - target workspace id
#   masterEntry   - saved master "address:class"
#   $3 (nameref)  - array of saved slave "address:class" entries, in order
restore_workspace_master() {
    local wsId="$1"
    local masterEntry="$2"
    local -n slaveEntries="$3"

    local masterAddr="${masterEntry%%:*}"
    local masterClass=$(extract_class "$masterEntry")

    local masterOrientation
    masterOrientation=$(hyprctl getoption master:orientation -j | jq -r '.str')

    echo "Restoring workspace $wsId (master: $masterClass)"

    # One snapshot covers selector resolution for the master and every
    # slave, plus the master check below — nothing is dispatched until
    # after that check, so a single fetch is valid for all of it.
    local clientsJson
    clientsJson=$(hyprctl clients -j)

    local masterSel
    masterSel=$(resolve_client "$masterAddr" "$masterClass" "$clientsJson" | sed -n '1p')
    if [ -z "$masterSel" ]; then
        echo "  Skipping master $masterClass (not currently open, or ambiguous duplicates)"
    fi

    # Nothing more to do for a single-window workspace — it's already on
    # the right workspace, with no ordering to fix.
    if [ ${#slaveEntries[@]} -eq 0 ]; then
        return
    fi

    # Build selectors for each slave (used below for focus/swap dispatches).
    # Cross-workspace placement already happened before this function runs,
    # so this function only deals with internal ordering (who's master,
    # slot order).
    local -a slaveSels=()
    for entry in "${slaveEntries[@]}"; do
        local slaveAddr="${entry%%:*}"
        local slaveClass=$(extract_class "$entry")
        local slaveSel
        slaveSel=$(resolve_client "$slaveAddr" "$slaveClass" "$clientsJson" | sed -n '1p')
        if [ -z "$slaveSel" ]; then
            echo "  Skipping $slaveClass (not currently open, or ambiguous duplicates)"
        fi
        slaveSels+=("$slaveSel")
    done

    # Step 1: set correct master only if needed (still using the same
    # snapshot fetched above — nothing's been dispatched yet).
    if [ -n "$masterSel" ]; then
        local currentMasterAddr
        currentMasterAddr=$(printf '%s' "$clientsJson" | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $wsId]
if not ws_clients:
    exit(1)
orientation = '$masterOrientation'
max_area = max(c['size'][0] * c['size'][1] for c in ws_clients)
candidates = [c for c in ws_clients if c['size'][0] * c['size'][1] == max_area]
if len(candidates) == 1:
    master = candidates[0]
elif orientation == 'right':
    master = max(candidates, key=lambda x: x['at'][0])
elif orientation == 'top':
    master = min(candidates, key=lambda x: x['at'][1])
elif orientation == 'bottom':
    master = max(candidates, key=lambda x: x['at'][1])
else:
    master = min(candidates, key=lambda x: x['at'][0])
print(master['address'])
" 2>/dev/null)

        # Confirm current master's address against our resolved target
        # window's actual address (not the possibly-stale saved one).
        local masterResolvedAddr
        masterResolvedAddr=$(resolve_client "$masterAddr" "$masterClass" "$clientsJson" | sed -n '2p')

        if [ -n "$currentMasterAddr" ] && [ -n "$masterResolvedAddr" ] && [ "$currentMasterAddr" != "$masterResolvedAddr" ]; then
            echo "  Promoting $masterClass to master on ws $wsId"
            hyprctl dispatch "hl.dsp.focus({ window = \"$masterSel\", follow = false })" 2>/dev/null
            sleep 0.3
            hyprctl dispatch 'hl.dsp.layout("swapwithmaster master")'
            sleep 0.3
        fi
    fi

    # Step 2: restore each slave slot in order. Each iteration genuinely
    # needs a FRESH snapshot — an earlier swap in this loop changes slot
    # order for everyone after it — but the two lookups within ONE
    # iteration (resolved address + current slot) share that one fetch.
    for targetSlot in "${!slaveEntries[@]}"; do
        local targetSel="${slaveSels[$targetSlot]}"
        [ -z "$targetSel" ] && continue   # skipped entry, nothing to slot

        local targetAddr="${slaveEntries[$targetSlot]%%:*}"
        local targetClass=$(extract_class "${slaveEntries[$targetSlot]}")

        local slotClientsJson
        slotClientsJson=$(hyprctl clients -j)

        # Resolve to the window's actual current address first (handles a
        # stale saved address when the class is still unique), then find
        # its slot index among current slaves.
        local resolvedAddr
        resolvedAddr=$(resolve_client "$targetAddr" "$targetClass" "$slotClientsJson" | sed -n '2p')
        [ -z "$resolvedAddr" ] && continue

        local currentSlot
        currentSlot=$(printf '%s' "$slotClientsJson" | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $wsId]
if not ws_clients:
    exit(1)
orientation = '$masterOrientation'
max_area = max(c['size'][0] * c['size'][1] for c in ws_clients)
candidates = [c for c in ws_clients if c['size'][0] * c['size'][1] == max_area]
if len(candidates) == 1:
    master = candidates[0]
elif orientation == 'right':
    master = max(candidates, key=lambda x: x['at'][0])
elif orientation == 'top':
    master = min(candidates, key=lambda x: x['at'][1])
elif orientation == 'bottom':
    master = max(candidates, key=lambda x: x['at'][1])
else:
    master = min(candidates, key=lambda x: x['at'][0])
slaves = [c for c in ws_clients if c['address'] != master['address']]
addr = '$resolvedAddr'
for i, c in enumerate(sorted(slaves, key=lambda x: (x['at'][1], x['at'][0]))):
    if c['address'] == addr:
        print(i); break
" 2>/dev/null)

        if [ -n "$currentSlot" ] && [ "$currentSlot" -gt 0 ]; then
            local swapCount=$(( currentSlot - targetSlot ))
            if [ $swapCount -gt 0 ]; then
                echo "  Moving slot $currentSlot to slot $targetSlot"
                hyprctl dispatch "hl.dsp.focus({ window = \"$targetSel\", follow = false })" 2>/dev/null
                sleep 0.2
                for i in $(seq 1 $swapCount); do
                    hyprctl dispatch 'hl.dsp.layout("swapprev")'
                    sleep 0.2
                done
            fi
        fi
    done
}