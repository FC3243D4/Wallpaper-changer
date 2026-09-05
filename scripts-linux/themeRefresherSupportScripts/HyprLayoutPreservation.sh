#!/usr/bin/env bash
# HyprLayoutPreservation.sh
# Saves and restores Hyprland window layout across all workspaces, so
# arrangement survives events that scatter windows (e.g. a theme refresh
# restarting several apps at once).
#
# Handles all four Hyprland layouts, including mixed setups where
# different workspaces run different layouts at once:
#   - master    : ordered via swapwithmaster/swapprev
#   - dwindle   : rebuilt via evict-and-reinsert plus a directional-move
#                 grid-correction pass (no reorder dispatcher exists)
#   - scrolling : rebuilt via evict-and-reinsert with directional merges,
#                 then a bounded up/down pass to fix row order per column
#   - monocle   : has no reorder dispatcher and no passive geometry signal
#                 (every window occupies the same rect), so save actively
#                 walks cyclenext to capture order, and restore reinserts
#                 in reverse (each insert becomes the new top of stack)
#
# Each workspace's live layout is read from `hyprctl workspaces -j`'s
# `tiledLayout` field (Hyprland 0.54+), reflecting whatever's actually
# active right now regardless of how it was set. `general:layout` is only
# a last-resort fallback for a workspace that field doesn't report.
#
# Usage:
#   HyprLayoutPreservation.sh save
#   HyprLayoutPreservation.sh restore

stateFile="/tmp/hyprLayoutState.txt"

# Scratch workspace used to "evict" windows (dwindle/scrolling/monocle) so
# their internal position is forgotten before being reinserted in order.
dwindleScratchWorkspace="special:layoutscratch"

get_layout_mode() {
    hyprctl getoption general:layout -j | jq -r '.str'
}

save_layout() {
    local currentWorkspace
    currentWorkspace=$(hyprctl activeworkspace -j | jq '.id')
    local defaultLayout
    defaultLayout=$(get_layout_mode)
    echo "Current workspace: $currentWorkspace"
    echo "Default layout mode: $defaultLayout"

    local workspaceLayoutsJson
    workspaceLayoutsJson=$(hyprctl workspaces -j)
    local layoutOverridesArg
    layoutOverridesArg=$(echo "$workspaceLayoutsJson" | jq -r '.[] | select(.tiledLayout != null) | "\(.id)=\(.tiledLayout)"' | paste -sd, -)
    if [ -n "$layoutOverridesArg" ]; then
        echo "Live per-workspace layouts: ${layoutOverridesArg}"
    fi

    local masterOrientation
    masterOrientation=$(hyprctl getoption master:orientation -j | jq -r '.str')

    # One fetch covers both this snapshot and the allWorkspaceIds lookup
    # below — nothing is dispatched in between, so it stays valid for both.
    local clientsJson
    clientsJson=$(hyprctl clients -j)

    {
        echo "current_workspace:$currentWorkspace"
        echo "default_layout:$defaultLayout"

        # Each workspace's EFFECTIVE layout (live tiledLayout if reported,
        # else the global default) is decided here and saved directly as a
        # "wslayout:" line, so restore never needs to query hyprctl for
        # it — it just uses what was actually true at save time.
        printf '%s' "$clientsJson" | python3 -c "
import json, sys
clients = json.load(sys.stdin)
default_layout = '$defaultLayout'
orientation = '$masterOrientation'
ws_layouts_raw = '$layoutOverridesArg'
ws_layouts = {}
for pair in ws_layouts_raw.split(','):
    if '=' in pair:
        k, v = pair.split('=', 1)
        ws_layouts[k] = v

def effective_layout(ws_id):
    # Live tiledLayout from hyprctl workspaces -j; falls back to
    # general:layout only if that workspace wasn't reported (shouldn't
    # normally happen for any workspace with open clients).
    return ws_layouts.get(str(ws_id), default_layout)

def pick_master(ws_clients):
    max_area = max(c['size'][0] * c['size'][1] for c in ws_clients)
    candidates = [c for c in ws_clients if c['size'][0] * c['size'][1] == max_area]
    if len(candidates) == 1:
        return candidates[0]
    # Equal-area tie (e.g. a plain 2-window 50/50 split) — size alone can't
    # tell master from slave, so fall back to position along the axis the
    # configured master:orientation actually places the master pane on.
    if orientation == 'right':
        return max(candidates, key=lambda x: x['at'][0])
    elif orientation == 'top':
        return min(candidates, key=lambda x: x['at'][1])
    elif orientation == 'bottom':
        return max(candidates, key=lambda x: x['at'][1])
    else:  # 'left' (default) or 'center'/unrecognized
        return min(candidates, key=lambda x: x['at'][0])

workspaces = {}
for c in clients:
    ws_id = c['workspace']['id']
    if ws_id <= 0:
        continue
    workspaces.setdefault(ws_id, []).append(c)

for ws_id, ws_clients in sorted(workspaces.items()):
    layout = effective_layout(ws_id)
    if layout == 'monocle':
        continue  # handled separately — needs active cycling, not passive geometry
    print('workspace:' + str(ws_id))
    print('wslayout:' + layout)

    if layout == 'master':
        if len(ws_clients) == 1:
            c = ws_clients[0]
            print('master:' + c['address'] + ':' + c['class'])
            print('---')
            continue
        master = pick_master(ws_clients)
        slaves = [c for c in ws_clients if c['address'] != master['address']]
        print('master:' + master['address'] + ':' + master['class'])
        for c in sorted(slaves, key=lambda x: (x['at'][1], x['at'][0])):
            print('slave:' + c['address'] + ':' + c['class'])
        print('---')
    elif layout == 'scrolling':
        # Windows sharing the same column stack vertically at an identical
        # left-edge x position, so that's a reliable clustering key. Columns
        # are ordered left-to-right, and each column's windows top-to-bottom.
        cols = {}
        for c in ws_clients:
            x = c['at'][0]
            cols.setdefault(x, []).append(c)
        for col_idx, x in enumerate(sorted(cols.keys())):
            col_clients = sorted(cols[x], key=lambda c: c['at'][1])
            for row_idx, c in enumerate(col_clients):
                at = c.get('at', [0, 0])
                size = c.get('size', [0, 0])
                print('window:' + c['address'] + ':' + c['class'] + ':' +
                      str(at[0]) + ':' + str(at[1]) + ':' + str(size[0]) + ':' + str(size[1]) + ':' +
                      str(col_idx) + ':' + str(row_idx))
        print('---')
    else:
        # dwindle (or any other unrecognized layout): capture raster order
        # (top-to-bottom, left-to-right) as a proxy for insertion order,
        # plus each window's actual position/size for grid correction.
        ordered = sorted(ws_clients, key=lambda x: (x['at'][1], x['at'][0]))
        for c in ordered:
            at = c.get('at', [0, 0])
            size = c.get('size', [0, 0])
            print('window:' + c['address'] + ':' + c['class'] + ':' +
                  str(at[0]) + ':' + str(at[1]) + ':' + str(size[0]) + ':' + str(size[1]))
        print('---')
"
    } > "$stateFile"

    # Monocle workspaces have no passive geometry signal, so their cycle
    # order can only be captured by switching to the workspace and walking
    # cyclenext, recording which window becomes visible at each step. This
    # briefly disrupts the view for monocle workspaces only — every other
    # layout above is captured passively, with zero side effects.
    local allWorkspaceIds
    allWorkspaceIds=$(printf '%s' "$clientsJson" | jq -r '[.[].workspace.id] | unique | .[]')
    for wsId in $allWorkspaceIds; do
        [ "$wsId" -le 0 ] 2>/dev/null && continue

        local thisLayout="$defaultLayout"
        IFS=',' read -ra workspaceLayoutPairs <<< "$layoutOverridesArg"
        for pair in "${workspaceLayoutPairs[@]}"; do
            [ "${pair%%=*}" = "$wsId" ] && thisLayout="${pair#*=}"
        done

        if [ "$thisLayout" = "monocle" ]; then
            echo "Capturing monocle cycle order for workspace $wsId..."
            hyprctl dispatch "hl.dsp.focus({ workspace = $wsId })" >/dev/null 2>&1
            sleep 0.2

            local total
            total=$(hyprctl clients -j | jq -r --argjson w "$wsId" '[.[] | select(.workspace.id == $w)] | length')

            local -a monocleOrder=()
            if [ "$total" -gt 0 ] 2>/dev/null; then
                local startAddr=""
                for (( i = 0; i < total; i++ )); do
                    local cur
                    cur=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_id = $wsId
for c in clients:
    if c['workspace']['id'] == ws_id and c.get('visible'):
        print(c['address'] + '|' + c['class'])
        break
" 2>/dev/null)
                    [ -z "$cur" ] && break
                    local curAddr="${cur%%|*}"

                    if [ "$i" -eq 0 ]; then
                        startAddr="$curAddr"
                    elif [ "$curAddr" = "$startAddr" ]; then
                        break   # cycled back to the start
                    fi

                    monocleOrder+=("$cur")
                    hyprctl dispatch 'hl.dsp.layout("cyclenext")' >/dev/null 2>&1
                    sleep 0.15
                done
            fi

            {
                echo "workspace:$wsId"
                echo "wslayout:monocle"
                for entry in "${monocleOrder[@]}"; do
                    local addr="${entry%%|*}"
                    local cls="${entry#*|}"
                    echo "monowindow:${addr}:${cls}"
                done
                echo "---"
            } >> "$stateFile"
        fi
    done

    # Return to wherever the view started before any monocle cycle-walking
    hyprctl dispatch "hl.dsp.focus({ workspace = $currentWorkspace })" >/dev/null 2>&1

    if [ -s "$stateFile" ]; then
        echo "Layout saved for workspaces:"
        grep "^workspace:" "$stateFile" | cut -d: -f2
    else
        echo "No layouts found to save"
        rm -f "$stateFile"
    fi
}

# Extracts the class field from an "address:class[:extra:fields...]" entry.
# Safe for plain "address:class" pairs too (no-op if there's no further colon).
extract_class() {
    local entry="$1"
    local rest="${entry#*:}"
    echo "${rest%%:*}"
}

# Resolves a saved (address, class) pair against a SNAPSHOT of
# `hyprctl clients -j` output passed in by the caller (never fetched
# here), using one strategy throughout this script:
#   - 0 current matches -> nothing found, caller should skip
#   - 1 current match    -> unambiguous; selector "class:$class"
#   - 2+ current matches -> only usable if the exact saved (address+class)
#                           pair is still among them -> "address:0x...";
#                           otherwise ambiguous, nothing found
# Class matching is the default and is safe by construction (no risk of a
# killed app's freed address being recycled for an entirely different
# app's new window). Address is only used to disambiguate when multiple
# windows currently share the saved class.
#
# Prints 3 lines on success (empty output on failure):
#   1. selector        ("class:X" or "address:0x...")
#   2. current address  (may differ from the saved one if stale)
#   3. current workspace id
# Callers pick whichever lines they need with `sed -n 'Np'` — pure
# in-memory JSON filtering, so calling this repeatedly against the same
# cached snapshot costs nothing extra.
#   $1 - saved address
#   $2 - saved class
#   $3 - clients JSON snapshot (output of `hyprctl clients -j`)
resolve_client() {
    local addr="$1" class="$2" clientsJson="$3"
    printf '%s' "$clientsJson" | python3 -c "
import json, sys
clients = json.load(sys.stdin)
addr = '$addr'
cls = '$class'.lower()
matches = [c for c in clients if cls in c.get('class', '').lower()]
target = None
if len(matches) == 1:
    target = matches[0]
elif len(matches) > 1:
    for c in matches:
        if c['address'] == addr:
            target = c
            break
if target is None:
    sys.exit(0)
sel = 'class:' + '$class' if len(matches) == 1 else 'address:' + target['address']
print(sel)
print(target['address'])
print(target['workspace']['id'])
" 2>/dev/null
}

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

# Compares each saved dwindle window's position against its current one
# and issues window.move direction corrections to fix grid placement (e.g.
# a 2x2 quarters layout). Bucketing into "lo"/"hi" halves (rather than
# exact coordinates) only fixes which half/quadrant a window belongs in,
# not exact pixel geometry — that's what a directional move can actually
# influence.
#   wsId          - target workspace id
#   $2 (nameref)  - array of saved "address:class:atx:aty:w:h" entries
correct_dwindle_geometry() {
    local wsId="$1"
    local -n geometryEntries="$2"

    if [ ${#geometryEntries[@]} -lt 2 ]; then
        return
    fi

    local geometryFile
    geometryFile=$(mktemp /tmp/hyprDwindleGeom.XXXXXX)
    printf '%s\n' "${geometryEntries[@]}" > "$geometryFile"

    for attempt in 1 2 3 4; do
        local actions
        actions=$(hyprctl clients -j | python3 -c "
import json, sys

current = json.load(sys.stdin)
ws_id = $wsId
saved = []
with open('$geometryFile') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split(':')
        if len(parts) < 6:
            continue
        addr, cls, atx, aty, w, h = parts[0], parts[1], int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5])
        saved.append({'addr': addr, 'class': cls, 'atx': atx, 'aty': aty})

ws_clients = [c for c in current if c['workspace']['id'] == ws_id]
if len(saved) < 2 or not ws_clients:
    sys.exit(0)

xs = [s['atx'] for s in saved]
ys = [s['aty'] for s in saved]
min_x, max_x = min(xs), max(xs)
min_y, max_y = min(ys), max(ys)
has_h = (max_x - min_x) > 15
has_v = (max_y - min_y) > 15
mid_x = (min_x + max_x) / 2
mid_y = (min_y + max_y) / 2

def bucket(v, mid):
    return 'lo' if v < mid else 'hi'

def resolve_current(s):
    # Class-first: safe by construction, no address-reuse risk. Address
    # only disambiguates if multiple windows of this class are currently
    # on this workspace.
    matches = [c for c in ws_clients if s['class'].lower() in c.get('class', '').lower()]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        for c in matches:
            if c['address'] == s['addr']:
                return c
    return None

for s in saved:
    cur = resolve_current(s)
    if cur is None:
        continue
    cur_x, cur_y = cur['at'][0], cur['at'][1]
    if has_h:
        target_h = bucket(s['atx'], mid_x)
        current_h = bucket(cur_x, mid_x)
        if target_h != current_h:
            direction = 'l' if target_h == 'lo' else 'r'
            print('address:' + cur['address'] + '|' + direction)
    if has_v:
        target_v = bucket(s['aty'], mid_y)
        current_v = bucket(cur_y, mid_y)
        if target_v != current_v:
            direction = 'u' if target_v == 'lo' else 'd'
            print('address:' + cur['address'] + '|' + direction)
" 2>/dev/null)

        if [ -z "$actions" ]; then
            break
        fi

        while IFS='|' read -r sel direction; do
            [ -z "$sel" ] && continue
            echo "  Adjusting grid position: focusing $sel, move $direction"
            hyprctl dispatch "hl.dsp.focus({ window = \"$sel\", follow = false })" 2>/dev/null
            sleep 0.2
            hyprctl dispatch "hl.dsp.window.move({ direction = \"$direction\" })" 2>/dev/null
            sleep 0.2
        done <<< "$actions"
    done

    rm -f "$geometryFile"
}

# Restores a single dwindle-layout workspace. Dwindle has no master/slave
# concept — order comes purely from the split tree, built incrementally as
# windows are inserted. Rather than compute/replay tree splits, evict all
# windows to a scratch workspace (forgetting their old tree position),
# then bring them back one at a time in saved order, which drives dwindle
# to rebuild the tree in that same order. A geometry-correction pass then
# fixes up grid placement that insertion order alone can't guarantee.
#   wsId          - target workspace id
#   $2 (nameref)  - array of saved "address:class:atx:aty:w:h" entries,
#                   in raster (top-to-bottom, left-to-right) order
restore_workspace_dwindle() {
    local wsId="$1"
    local -n windowEntries="$2"

    echo "Restoring workspace $wsId (dwindle, ${#windowEntries[@]} windows)"

    if [ ${#windowEntries[@]} -eq 0 ]; then
        return
    fi

    if [ ${#windowEntries[@]} -eq 1 ]; then
        return   # nothing to order — already on the right workspace
    fi

    local -a movableSels=()
    local clientsJson
    clientsJson=$(hyprctl clients -j)
    for entry in "${windowEntries[@]}"; do
        local addr="${entry%%:*}"
        local class=$(extract_class "$entry")
        local sel
        sel=$(resolve_client "$addr" "$class" "$clientsJson" | sed -n '1p')
        if [ -z "$sel" ]; then
            echo "  Skipping $class (not currently open, or ambiguous duplicates)"
        else
            movableSels+=("$sel")
        fi
    done

    if [ ${#movableSels[@]} -eq 0 ]; then
        return
    fi

    # Step 1: evict to scratch, forgetting current tree position
    for sel in "${movableSels[@]}"; do
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$dwindleScratchWorkspace\", window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
    done

    # Step 2: reinsert one at a time, in saved order, rebuilding the split
    # tree in that sequence. Dwindle splits off whichever window is
    # currently focused, so each window must be explicitly focused right
    # after moving it in — otherwise later windows keep splitting against
    # stale focus instead of chaining off the previous insert, scrambling
    # the order.
    for sel in "${movableSels[@]}"; do
        hyprctl dispatch "hl.dsp.window.move({ workspace = $wsId, window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
        hyprctl dispatch "hl.dsp.focus({ window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
    done

    # Step 3: correct grid placement (e.g. a 2x2 quarters layout coming
    # out as an L-shape), since dwindle picks each split's orientation
    # from the aspect ratio at insertion time, not the saved layout.
    correct_dwindle_geometry "$wsId" windowEntries
}

# Restores a single scrolling-layout workspace. Scrolling arranges windows
# in left-to-right columns, each column able to stack multiple windows.
# Confirmed behavior this relies on:
#   - a window arriving on the workspace always becomes its own new column
#   - directional move left merges the focused window into the PREVIOUS
#     column, appending it at the BOTTOM of that column's stack
#   - only the focused window moves — other former column-mates stay put
#
# So: evict everyone to scratch (forgetting current columns), then
# reinsert in saved column-major/row-minor order — each column's first
# window just gets inserted and focused (starts a fresh column); every
# later window in that SAME column is inserted (its own new column) then
# immediately merged left into the column being built, which — since rows
# are processed top-to-bottom — reconstructs the correct stack order.
# Staying focused on whatever was just placed keeps new columns appending
# right after the last one, preserving left-to-right column order.
#   wsId          - target workspace id
#   $2 (nameref)  - array of saved "address:class:atx:aty:w:h:colidx:rowidx"
#                   entries, in column-major/row-minor saved order
restore_workspace_scrolling() {
    local wsId="$1"
    local -n scrollEntries="$2"

    echo "Restoring workspace $wsId (scrolling, ${#scrollEntries[@]} windows)"

    if [ ${#scrollEntries[@]} -le 1 ]; then
        return   # nothing to order — already on the right workspace
    fi

    # Resolve selectors and pull out each entry's column/row indices (last
    # two fields), preserving saved order (already column-major/row-minor).
    local -a sels=()
    local -a columnIndexes=()
    local -a rowIndexes=()
    local clientsJson
    clientsJson=$(hyprctl clients -j)
    for entry in "${scrollEntries[@]}"; do
        local addr="${entry%%:*}"
        local class=$(extract_class "$entry")
        local rowIndex="${entry##*:}"
        local tmp="${entry%:*}"
        local columnIndex="${tmp##*:}"

        local sel
        sel=$(resolve_client "$addr" "$class" "$clientsJson" | sed -n '1p')
        if [ -z "$sel" ]; then
            echo "  Skipping $class (not currently open, or ambiguous duplicates)"
            continue
        fi
        sels+=("$sel")
        columnIndexes+=("$columnIndex")
        rowIndexes+=("$rowIndex")
    done

    if [ ${#sels[@]} -eq 0 ]; then
        return
    fi

    # Step 1: evict to scratch, forgetting current column structure
    for sel in "${sels[@]}"; do
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$dwindleScratchWorkspace\", window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
    done

    # Step 2: reinsert in saved order, merging same-column entries left.
    # This reliably rebuilds correct COLUMN membership, but not necessarily
    # correct row order within a column — merging into an existing column
    # doesn't always land at the bottom; the exact slot depends on the
    # column's current parity/history, not worth reverse-engineering.
    # Step 3 fixes row order afterward instead.
    local prevColumnIndex=""
    for i in "${!sels[@]}"; do
        local sel="${sels[$i]}"
        local columnIndex="${columnIndexes[$i]}"

        hyprctl dispatch "hl.dsp.window.move({ workspace = $wsId, window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.2
        hyprctl dispatch "hl.dsp.focus({ window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.2

        if [ "$columnIndex" = "$prevColumnIndex" ]; then
            hyprctl dispatch "hl.dsp.window.move({ direction = \"l\" })" 2>/dev/null
            sleep 0.2
        fi

        prevColumnIndex="$columnIndex"
    done

    # Step 3: correct row order within each column using bounded up/down
    # moves (confirmed to stop at the column's top/bottom rather than
    # wrapping or leaving the column), bubble-sorting each window into its
    # saved row position — same technique used for master's slot order.
    for attempt in 1 2 3 4 5; do
        local corrected=0
        for i in "${!sels[@]}"; do
            local sel="${sels[$i]}"
            local desiredRow="${rowIndexes[$i]}"

            local currentRank
            currentRank=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
sel = '$sel'
ws_id = $wsId
ws_clients = [c for c in clients if c['workspace']['id'] == ws_id]

target = None
if sel.startswith('address:'):
    addr = sel[len('address:'):]
    for c in ws_clients:
        if c['address'] == addr:
            target = c
            break
elif sel.startswith('class:'):
    cls = sel[len('class:'):].lower()
    matches = [c for c in ws_clients if cls in c.get('class', '').lower()]
    if len(matches) == 1:
        target = matches[0]

if target is None:
    sys.exit(0)

x = target['at'][0]
col_clients = sorted([c for c in ws_clients if c['at'][0] == x], key=lambda c: c['at'][1])
for idx, c in enumerate(col_clients):
    if c['address'] == target['address']:
        print(idx)
        break
" 2>/dev/null)

            if [ -n "$currentRank" ] && [ "$currentRank" != "$desiredRow" ]; then
                hyprctl dispatch "hl.dsp.focus({ window = \"$sel\", follow = false })" 2>/dev/null
                sleep 0.15
                if [ "$currentRank" -gt "$desiredRow" ]; then
                    hyprctl dispatch "hl.dsp.window.move({ direction = \"u\" })" 2>/dev/null
                else
                    hyprctl dispatch "hl.dsp.window.move({ direction = \"d\" })" 2>/dev/null
                fi
                sleep 0.15
                corrected=1
            fi
        done
        [ "$corrected" -eq 0 ] && break
    done
}

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

case "$1" in
    save)    save_layout ;;
    restore) restore_layout ;;
    *)
        echo "Usage: $0 save|restore"
        exit 1
        ;;
esac