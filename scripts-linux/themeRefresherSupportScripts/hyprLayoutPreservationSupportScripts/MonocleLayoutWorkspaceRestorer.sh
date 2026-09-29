#!/usr/bin/env bash

# Restores a single monocle-layout workspace. Monocle has no native
# reordering dispatcher (only cyclenext/cycleprev, which move focus
# through whatever order already exists) and no positional signal to read
# passively — so this relies entirely on one confirmed fact: moving a
# window onto a monocle workspace always makes it the new top of the
# stack. That's a plain stack push, so inserting the saved entries in
# REVERSE order (bottom-of-stack first, top-of-stack last) reconstructs
# the original top-to-bottom order with no reordering command at all.
#   wsId          - target workspace id
#   $2 (nameref)  - array of saved "address:class" entries, top-to-bottom
#                   cycle order as captured at save time
restore_workspace_monocle() {
    local wsId="$1"
    local -n monocleEntries="$2"

    echo "Restoring workspace $wsId (monocle, ${#monocleEntries[@]} windows)"

    if [ ${#monocleEntries[@]} -le 1 ]; then
        return   # nothing to order — already on the right workspace
    fi

    local -a sels=()
    local clientsJson
    clientsJson=$(hyprctl clients -j)
    for entry in "${monocleEntries[@]}"; do
        local addr="${entry%%:*}"
        local class=$(extract_class "$entry")
        local sel
        sel=$(resolve_client "$addr" "$class" "$clientsJson" | sed -n '1p')
        if [ -z "$sel" ]; then
            echo "  Skipping $class (not currently open, or ambiguous duplicates)"
        else
            sels+=("$sel")
        fi
    done

    if [ ${#sels[@]} -eq 0 ]; then
        return
    fi

    # Step 1: evict to scratch, forgetting current stack position
    for sel in "${sels[@]}"; do
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$dwindleScratchWorkspace\", window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
    done

    # Step 2: reinsert in REVERSE saved order — each insertion becomes the
    # new top, so inserting the saved bottom first and the saved top last
    # leaves the stack in the original order.
    local n=${#sels[@]}
    for (( i = n - 1; i >= 0; i-- )); do
        hyprctl dispatch "hl.dsp.window.move({ workspace = $wsId, window = \"${sels[$i]}\", follow = false })" 2>/dev/null
        sleep 0.2
    done
}

restore_layout() {
    if [ ! -f "$stateFile" ] || [ ! -s "$stateFile" ]; then
        echo "No saved layout state found, skipping restore"
        return
    fi

    local savedWorkspace
    savedWorkspace=$(grep "^current_workspace:" "$stateFile" | cut -d: -f2)
    local defaultLayout
    defaultLayout=$(grep "^default_layout:" "$stateFile" | cut -d: -f2)
    echo "Will return to workspace: $savedWorkspace"
    echo "Saved default layout mode: $defaultLayout"

    # === Parse pass: read the whole state file into memory first. No
    # restore actions happen here — build a flat list of every saved
    # window (for Phase 1) plus a per-workspace structure (for Phase 2),
    # keeping workspace order as it appeared in the file. Each workspace's
    # actual layout (which may differ per-workspace via a workspace rule)
    # comes from its own "wslayout:" line rather than a global assumption. ===
    local loopWorkspace=""
    local loopMaster=""
    local loopLayout=""
    declare -a loopSlaves
    declare -a loopWindows
    declare -a loopMonoWindows
    declare -a allEntries=()          # each "wsId|address:class[:...]"
    declare -a workspaceOrder=()      # workspace ids, in saved order
    declare -A workspaceLayoutMap     # wsId -> layout ("master", "dwindle", ...)
    declare -A workspaceMasterMap     # wsId -> "address:class" (master mode)
    declare -A workspaceSlavesMap     # wsId -> newline-joined slave entries
    declare -A workspaceWindowsMap    # wsId -> newline-joined window entries
    declare -A workspaceMonocleMap    # wsId -> newline-joined monowindow entries

    while IFS= read -r line; do
        if [[ "$line" == current_workspace:* ]] || [[ "$line" == default_layout:* ]]; then
            continue
        elif [[ "$line" == workspace:* ]]; then
            loopWorkspace="${line#workspace:}"
            loopMaster=""
            loopLayout=""
            loopSlaves=()
            loopWindows=()
            loopMonoWindows=()
        elif [[ "$line" == wslayout:* ]]; then
            loopLayout="${line#wslayout:}"
        elif [[ "$line" == master:* ]]; then
            loopMaster="${line#master:}"          # "address:class"
        elif [[ "$line" == slave:* ]]; then
            loopSlaves+=("${line#slave:}")          # "address:class"
        elif [[ "$line" == window:* ]]; then
            loopWindows+=("${line#window:}")        # "address:class:atx:aty:w:h"
        elif [[ "$line" == monowindow:* ]]; then
            loopMonoWindows+=("${line#monowindow:}")  # "address:class"
        elif [[ "$line" == "---" ]]; then
            if [ -n "$loopWorkspace" ] && [ -n "$loopMaster" ]; then
                allEntries+=("${loopWorkspace}|${loopMaster}")
            fi
            for e in "${loopSlaves[@]}"; do
                allEntries+=("${loopWorkspace}|${e}")
            done
            for e in "${loopWindows[@]}"; do
                allEntries+=("${loopWorkspace}|${e}")
            done
            for e in "${loopMonoWindows[@]}"; do
                allEntries+=("${loopWorkspace}|${e}")
            done

            if [ -n "$loopWorkspace" ]; then
                workspaceOrder+=("$loopWorkspace")
                workspaceLayoutMap["$loopWorkspace"]="${loopLayout:-$defaultLayout}"
                workspaceMasterMap["$loopWorkspace"]="$loopMaster"
                workspaceSlavesMap["$loopWorkspace"]=$(printf '%s\n' "${loopSlaves[@]}")
                workspaceWindowsMap["$loopWorkspace"]=$(printf '%s\n' "${loopWindows[@]}")
                workspaceMonocleMap["$loopWorkspace"]=$(printf '%s\n' "${loopMonoWindows[@]}")
            fi
            loopWorkspace=""
            loopMaster=""
            loopLayout=""
            loopSlaves=()
            loopWindows=()
            loopMonoWindows=()
        fi
    done < "$stateFile"

    # === Phase 1: move every saved window to its correct workspace first,
    # globally, before any per-workspace ordering runs. This decouples
    # "is everyone where they belong" from "what order are they in", so a
    # workspace's ordering logic never runs while a window meant for it is
    # still elsewhere (or vice versa). ===
    echo "Phase 1: moving all windows to their correct workspaces..."
    # One snapshot for the whole loop: a workspace-only move doesn't change
    # any window's class or address, so an earlier record's move can't
    # affect a later record's selector/ambiguity resolution — every record
    # is classified against the same pre-Phase-1 state, which is exactly
    # what "where did this window start" should mean anyway.
    local phase1ClientsJson
    phase1ClientsJson=$(hyprctl clients -j)
    for rec in "${allEntries[@]}"; do
        local recordWorkspace="${rec%%|*}"
        local recordRest="${rec#*|}"          # "address:class[:...]"
        local recordAddr="${recordRest%%:*}"
        local recordClass=$(extract_class "$recordRest")

        local resolved sel currentWorkspaceId
        resolved=$(resolve_client "$recordAddr" "$recordClass" "$phase1ClientsJson")
        sel=$(echo "$resolved" | sed -n '1p')
        if [ -z "$sel" ]; then
            echo "  Skipping $recordClass (not currently open, or ambiguous duplicates)"
            continue
        fi

        currentWorkspaceId=$(echo "$resolved" | sed -n '3p')
        if [ -n "$currentWorkspaceId" ] && [ "$currentWorkspaceId" != "$recordWorkspace" ]; then
            echo "  Moving $recordClass from ws $currentWorkspaceId to ws $recordWorkspace"
            hyprctl dispatch "hl.dsp.window.move({ workspace = $recordWorkspace, window = \"$sel\", follow = false })" 2>/dev/null
            sleep 0.2
        fi
    done

    # === Phase 2: now that everyone's on the right workspace, go
    # workspace by workspace and apply the layout-specific ordering
    # (master promotion + slot order, or dwindle tree rebuild + grid
    # correction, etc). ===
    echo "Phase 2: restoring layout order per workspace..."
    for wsId in "${workspaceOrder[@]}"; do
        local thisLayout="${workspaceLayoutMap[$wsId]}"
        if [ "$thisLayout" = "master" ]; then
            local thisMaster="${workspaceMasterMap[$wsId]}"
            if [ -n "$thisMaster" ]; then
                declare -a theseSlaves=()
                while IFS= read -r l; do
                    [ -n "$l" ] && theseSlaves+=("$l")
                done <<< "${workspaceSlavesMap[$wsId]}"
                restore_workspace_master "$wsId" "$thisMaster" theseSlaves
            fi
        elif [ "$thisLayout" = "scrolling" ]; then
            declare -a theseWindows=()
            while IFS= read -r l; do
                [ -n "$l" ] && theseWindows+=("$l")
            done <<< "${workspaceWindowsMap[$wsId]}"
            restore_workspace_scrolling "$wsId" theseWindows
        elif [ "$thisLayout" = "monocle" ]; then
            declare -a theseMono=()
            while IFS= read -r l; do
                [ -n "$l" ] && theseMono+=("$l")
            done <<< "${workspaceMonocleMap[$wsId]}"
            restore_workspace_monocle "$wsId" theseMono
        else
            declare -a theseWindows=()
            while IFS= read -r l; do
                [ -n "$l" ] && theseWindows+=("$l")
            done <<< "${workspaceWindowsMap[$wsId]}"
            restore_workspace_dwindle "$wsId" theseWindows
        fi
    done

    # Settle pass: some apps (e.g. launched with a hidden/delayed-start
    # flag) create their real window after Phase 1 has already moved on,
    # landing on whatever workspace happens to be active at that later
    # moment instead of the intended one. Re-check every saved window's
    # actual workspace a few times over ~1.5s and correct any stragglers.
    echo "Verifying window placement..."
    for attempt in 1 2 3; do
        local corrected=0
        local settleClientsJson
        settleClientsJson=$(hyprctl clients -j)
        for rec in "${allEntries[@]}"; do
            local recordWorkspace="${rec%%|*}"
            local recordRest="${rec#*|}"          # "address:class[:...]"
            local recordAddr="${recordRest%%:*}"
            local recordClass=$(extract_class "$recordRest")

            local resolved currentWorkspaceId
            resolved=$(resolve_client "$recordAddr" "$recordClass" "$settleClientsJson")
            currentWorkspaceId=$(echo "$resolved" | sed -n '3p')

            if [ -n "$currentWorkspaceId" ] && [ "$currentWorkspaceId" != "$recordWorkspace" ]; then
                local sel
                sel=$(echo "$resolved" | sed -n '1p')
                if [ -n "$sel" ]; then
                    echo "  Correcting $recordClass: ws $currentWorkspaceId -> ws $recordWorkspace"
                    hyprctl dispatch "hl.dsp.window.move({ workspace = $recordWorkspace, window = \"$sel\", follow = false })" 2>/dev/null
                    corrected=1
                fi
            fi
        done
        [ "$corrected" -eq 0 ] && break
        sleep 0.5
    done

    # Return to original workspace — retry until it sticks
    for i in $(seq 1 5); do
        sleep 0.3
        hyprctl dispatch "hl.dsp.focus({ workspace = $savedWorkspace })"
        current=$(hyprctl activeworkspace -j | jq '.id')
        [ "$current" = "$savedWorkspace" ] && break
    done

    rm -f "$stateFile"
    echo "Layout restore complete"
}