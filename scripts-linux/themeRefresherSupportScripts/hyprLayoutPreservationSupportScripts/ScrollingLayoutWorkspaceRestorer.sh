#!/usr/bin/env bash

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