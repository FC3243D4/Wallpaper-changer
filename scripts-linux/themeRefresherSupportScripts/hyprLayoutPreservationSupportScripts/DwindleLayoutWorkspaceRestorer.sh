#!/usr/bin/env bash

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