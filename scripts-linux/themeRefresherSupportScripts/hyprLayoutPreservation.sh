#!/usr/bin/env bash
# hyprMasterLayoutPreservation.sh
# Saves and restores Hyprland layout state for ALL tiled workspaces.
# Supports both the "master" layout (master/slave stack) and the
# "dwindle" layout (binary split tree).
#
# Usage:
#   hyprMasterLayoutPreservation.sh save
#   hyprMasterLayoutPreservation.sh restore

STATE_FILE="/tmp/hyprLayoutState.txt"

# Scratch workspace used to "evict" dwindle windows so their tree
# position is forgotten before being reinserted in the saved order.
DWINDLE_SCRATCH_WS="special:layoutscratch"

get_layout_mode() {
    hyprctl getoption general:layout -j | jq -r '.str'
}

# Path to the user's per-workspace rules file, following Hyprland Lua syntax
# like: hl.workspace_rule({ workspace = "2", layout = "scrolling" })
WORKSPACE_RULES_FILE="$HOME/.config/hypr/UserConfigs/WorkSpaceRules.lua"

# Scans WORKSPACE_RULES_FILE for hl.workspace_rule({...}) calls that set both
# a "workspace" and a "layout" field, and prints one "ws_id:layout" pair per
# line for each override found. A workspace with no matching rule simply
# isn't printed — callers should fall back to the global default in that case.
get_workspace_layout_overrides() {
    [ -f "$WORKSPACE_RULES_FILE" ] || return 0
    python3 -c "
import re

path = '$WORKSPACE_RULES_FILE'
try:
    with open(path) as f:
        content = f.read()
except OSError:
    raise SystemExit

# Strip Lua comments first, so a commented-out example rule (very common in
# this file, e.g. the stock wiki examples) is never mistaken for an active
# override. Block comments (--[[ ... ]]) first, then line comments (-- ...).
content = re.sub(r'--\[\[.*?\]\]', '', content, flags=re.DOTALL)
content = re.sub(r'--.*', '', content)

for block in re.findall(r'hl\.workspace_rule\s*\(\s*\{(.*?)\}\s*\)', content, re.DOTALL):
    ws_match = re.search(r'workspace\s*=\s*[\"\']?(\d+)[\"\']?', block)
    layout_match = re.search(r'layout\s*=\s*[\"\']([A-Za-z_]+)[\"\']', block)
    if ws_match and layout_match:
        print(ws_match.group(1) + ':' + layout_match.group(1))
" 2>/dev/null
}

save_layout() {
    local current_ws
    current_ws=$(hyprctl activeworkspace -j | jq '.id')
    local default_layout
    default_layout=$(get_layout_mode)
    echo "Current workspace: $current_ws"
    echo "Default layout mode: $default_layout"

    local overrides_arg=""
    while IFS=':' read -r ov_ws ov_layout; do
        [ -n "$ov_ws" ] && overrides_arg+="${ov_ws}=${ov_layout},"
    done < <(get_workspace_layout_overrides)
    if [ -n "$overrides_arg" ]; then
        echo "Workspace layout overrides: ${overrides_arg%,}"
    fi

    local master_orientation
    master_orientation=$(hyprctl getoption master:orientation -j | jq -r '.str')

    {
        echo "current_workspace:$current_ws"
        echo "default_layout:$default_layout"

        # Each workspace's EFFECTIVE layout (override if one exists for it,
        # else the global default) is decided here and saved directly per
        # workspace as a "wslayout:" line, so restore doesn't need to
        # re-read general:layout or the rules file — it just uses what was
        # actually true at save time.
        hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
default_layout = '$default_layout'
orientation = '$master_orientation'
overrides_raw = '$overrides_arg'
overrides = {}
for pair in overrides_raw.split(','):
    if '=' in pair:
        k, v = pair.split('=', 1)
        overrides[k] = v

def effective_layout(ws_id):
    return overrides.get(str(ws_id), default_layout)

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
    else:
        # dwindle (or any other non-master layout): capture raster order
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
    } > "$STATE_FILE"

    if [ -s "$STATE_FILE" ]; then
        echo "Layout saved for workspaces:"
        grep "^workspace:" "$STATE_FILE" | cut -d: -f2
    else
        echo "No layouts found to save"
        rm -f "$STATE_FILE"
    fi
}

# Extracts just the class field from an "address:class[:extra:fields...]"
# entry. Safe for plain "address:class" pairs too (no-op if no further colon).
extract_class() {
    local entry="$1"
    local rest="${entry#*:}"
    echo "${rest%%:*}"
}

# Resolve the safest window selector for a saved (address, class) pair.
# Class matching is the default and is safe by construction — it carries
# no risk of the address-reuse problem (a killed app's freed address being
# recycled by the compositor for an entirely different app's new window).
# Address is only used to disambiguate the rare case where MULTIPLE
# windows currently share this class and we need to know which specific
# one we saved:
#   - 0 current matches -> nothing to move, skip
#   - 1 current match    -> "class:$class" (unambiguous, no address needed)
#   - 2+ current matches -> only usable if the exact saved (address+class)
#                           pair is still among them -> "address:0x...";
#                           otherwise we can't safely tell which one we
#                           saved, so skip
resolve_selector() {
    local addr="$1"
    local class="$2"

    local match_count
    match_count=$(hyprctl clients -j | jq -r --arg c "${class,,}" \
        '[.[] | select((.class // "" | ascii_downcase | contains($c)))] | length' 2>/dev/null)
    [ -z "$match_count" ] && match_count=0

    if [ "$match_count" -eq 0 ] 2>/dev/null; then
        return 1
    fi

    if [ "$match_count" -eq 1 ] 2>/dev/null; then
        echo "class:$class"
        return 0
    fi

    # Multiple current instances of this class — only safe if the exact
    # saved window (same address AND class) is still one of them.
    if [ -n "$addr" ] && hyprctl clients -j | jq -e --arg a "$addr" --arg c "${class,,}" \
        'any(.[]; .address == $a and (.class // "" | ascii_downcase | contains($c)))' >/dev/null 2>&1; then
        echo "address:$addr"
        return 0
    fi

    return 1
}

# Returns the JSON object for the CURRENT window matching a saved
# (address, class) pair, using the same class-first / address-to-
# disambiguate strategy as resolve_selector. Prints nothing if there's no
# safe match. Used by callers that need to read the window's current
# properties (workspace, position, etc.), not just build a selector string.
resolve_current_client() {
    local addr="$1"
    local class="$2"
    hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
addr = '$addr'
cls = '$class'.lower()
matches = [c for c in clients if cls in c.get('class', '').lower()]
if len(matches) == 1:
    print(json.dumps(matches[0]))
elif len(matches) > 1:
    for c in matches:
        if c['address'] == addr:
            print(json.dumps(c))
            break
" 2>/dev/null
}

# Restores a single master-layout workspace: places the saved master and
# slaves back on the right workspace, promotes the correct window to
# master, then bubble-sorts each slave into its saved slot via swapprev.
#   ws_id      - target workspace id
#   m_entry    - saved master "address:class"
#   $3 (nameref) - array of saved slave "address:class" entries, in order
restore_workspace_master() {
    local ws_id="$1"
    local m_entry="$2"
    local -n o_entries="$3"

    local m_addr="${m_entry%%:*}"
    local m_class=$(extract_class "$m_entry")

    local master_orientation
    master_orientation=$(hyprctl getoption master:orientation -j | jq -r '.str')

    echo "Restoring workspace $ws_id (master: $m_class)"

    local m_sel
    m_sel=$(resolve_selector "$m_addr" "$m_class") || m_sel=""
    if [ -z "$m_sel" ]; then
        echo "  Skipping master $m_class (not currently open, or ambiguous duplicates)"
    fi

    # Nothing more to do for a single-window workspace — Phase 1 already
    # placed it on the correct workspace, and there's no ordering to fix.
    if [ ${#o_entries[@]} -eq 0 ]; then
        return
    fi

    # Build selectors for each slave (used below for focus/swap dispatches).
    # Cross-workspace placement is Phase 1's job by this point, so this
    # function only deals with internal ordering (who's master, slot order).
    local -a slave_sels=()
    for entry in "${o_entries[@]}"; do
        local s_addr="${entry%%:*}"
        local s_class=$(extract_class "$entry")
        local s_sel
        s_sel=$(resolve_selector "$s_addr" "$s_class") || s_sel=""
        if [ -z "$s_sel" ]; then
            echo "  Skipping $s_class (not currently open, or ambiguous duplicates)"
        fi
        slave_sels+=("$s_sel")
    done

    # Step 1: set correct master only if needed
    if [ -n "$m_sel" ]; then
        local cur_master_addr
        cur_master_addr=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $ws_id]
if not ws_clients:
    exit(1)
orientation = '$master_orientation'
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
        local m_resolved_addr
        m_resolved_addr=$(resolve_current_client "$m_addr" "$m_class" | jq -r '.address // empty')

        if [ -n "$cur_master_addr" ] && [ -n "$m_resolved_addr" ] && [ "$cur_master_addr" != "$m_resolved_addr" ]; then
            echo "  Promoting $m_class to master on ws $ws_id"
            hyprctl dispatch "hl.dsp.focus({ window = \"$m_sel\", follow = false })" 2>/dev/null
            sleep 0.3
            hyprctl dispatch 'hl.dsp.layout("swapwithmaster master")'
            sleep 0.3
        fi
    fi

    # Step 2: restore each slave slot in order
    for target_slot in "${!o_entries[@]}"; do
        local target_sel="${slave_sels[$target_slot]}"
        [ -z "$target_sel" ] && continue   # skipped entry, nothing to slot

        local target_addr="${o_entries[$target_slot]%%:*}"
        local target_class=$(extract_class "${o_entries[$target_slot]}")

        # Resolve to the window's actual current address first (handles
        # the case where the saved address is stale but the class is
        # unique), then find its slot index among current slaves.
        local resolved_addr
        resolved_addr=$(resolve_current_client "$target_addr" "$target_class" | jq -r '.address // empty')
        [ -z "$resolved_addr" ] && continue

        local cur_slot
        cur_slot=$(hyprctl clients -j | python3 -c "
import json, sys
clients = json.load(sys.stdin)
ws_clients = [c for c in clients if c['workspace']['id'] == $ws_id]
if not ws_clients:
    exit(1)
orientation = '$master_orientation'
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
addr = '$resolved_addr'
for i, c in enumerate(sorted(slaves, key=lambda x: (x['at'][1], x['at'][0]))):
    if c['address'] == addr:
        print(i); break
" 2>/dev/null)

        if [ -n "$cur_slot" ] && [ "$cur_slot" -gt 0 ]; then
            local n_swaps=$(( cur_slot - target_slot ))
            if [ $n_swaps -gt 0 ]; then
                echo "  Moving slot $cur_slot to slot $target_slot"
                hyprctl dispatch "hl.dsp.focus({ window = \"$target_sel\", follow = false })" 2>/dev/null
                sleep 0.2
                for i in $(seq 1 $n_swaps); do
                    hyprctl dispatch 'hl.dsp.layout("swapprev")'
                    sleep 0.2
                done
            fi
        fi
    done
}

# Compares each saved dwindle window's position against its current one and
# issues window.move direction corrections to fix grid placement (e.g. a
# 2x2 quarters layout). Bucketing into "lo"/"hi" halves (rather than exact
# coordinates) means this only fixes which half/quadrant a window belongs
# in, not exact pixel geometry — that's what a directional move can
# actually influence.
#   ws_id        - target workspace id
#   $2 (nameref) - array of saved "address:class:atx:aty:w:h" entries
correct_dwindle_geometry() {
    local ws_id="$1"
    local -n g_entries="$2"

    if [ ${#g_entries[@]} -lt 2 ]; then
        return
    fi

    local geom_file
    geom_file=$(mktemp /tmp/hyprDwindleGeom.XXXXXX)
    printf '%s\n' "${g_entries[@]}" > "$geom_file"

    for attempt in 1 2 3 4; do
        local actions
        actions=$(hyprctl clients -j | python3 -c "
import json, sys

current = json.load(sys.stdin)
ws_id = $ws_id
saved = []
with open('$geom_file') as f:
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
    # Class-first: safe by construction, no address-reuse risk. Address is
    # only used to disambiguate if multiple windows of this class are
    # currently on this workspace.
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

    rm -f "$geom_file"
}

# Restores a single dwindle-layout workspace. Dwindle has no master/slave
# concept — order comes purely from the split tree, which is built
# incrementally as windows are inserted. Rather than try to compute/replay
# tree splits, we evict all windows from the workspace to a scratch
# workspace (forgetting their old tree position) and then bring them back
# one at a time in the saved order, which drives dwindle to rebuild the
# tree in that same order. A geometry-correction pass then fixes up grid
# placement that insertion order alone can't guarantee.
#   ws_id        - target workspace id
#   $2 (nameref) - array of saved "address:class:atx:aty:w:h" entries,
#                  in raster (top-to-bottom, left-to-right) order
restore_workspace_dwindle() {
    local ws_id="$1"
    local -n w_entries="$2"

    echo "Restoring workspace $ws_id (dwindle, ${#w_entries[@]} windows)"

    if [ ${#w_entries[@]} -eq 0 ]; then
        return
    fi

    if [ ${#w_entries[@]} -eq 1 ]; then
        # Nothing to order — Phase 1 already placed it on the right workspace.
        return
    fi

    local -a movable_sels=()
    for entry in "${w_entries[@]}"; do
        local addr="${entry%%:*}"
        local class=$(extract_class "$entry")
        local sel
        sel=$(resolve_selector "$addr" "$class") || sel=""
        if [ -z "$sel" ]; then
            echo "  Skipping $class (not currently open, or ambiguous duplicates)"
        else
            movable_sels+=("$sel")
        fi
    done

    if [ ${#movable_sels[@]} -eq 0 ]; then
        return
    fi

    # Step 1: evict to scratch, forgetting current tree position
    for sel in "${movable_sels[@]}"; do
        hyprctl dispatch "hl.dsp.window.move({ workspace = \"$DWINDLE_SCRATCH_WS\", window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
    done

    # Step 2: reinsert one at a time, in saved order, rebuilding the split
    # tree in that sequence. Dwindle splits off whichever window is
    # currently focused, so we must explicitly focus each window right
    # after moving it in — otherwise every later window keeps splitting
    # against the same stale focus instead of chaining off the previous
    # insert, which scrambles the order.
    for sel in "${movable_sels[@]}"; do
        hyprctl dispatch "hl.dsp.window.move({ workspace = $ws_id, window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
        hyprctl dispatch "hl.dsp.focus({ window = \"$sel\", follow = false })" 2>/dev/null
        sleep 0.15
    done

    # Step 3: correct grid placement (e.g. a 2x2 quarters layout coming out
    # as an L-shape), since dwindle picks each split's orientation from the
    # aspect ratio at insertion time, not from the saved layout.
    correct_dwindle_geometry "$ws_id" w_entries
}

restore_layout() {
    if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        echo "No saved layout state found, skipping restore"
        return
    fi

    local saved_workspace
    saved_workspace=$(grep "^current_workspace:" "$STATE_FILE" | cut -d: -f2)
    local default_layout
    default_layout=$(grep "^default_layout:" "$STATE_FILE" | cut -d: -f2)
    echo "Will return to workspace: $saved_workspace"
    echo "Saved default layout mode: $default_layout"

    # === Parse pass: read the whole state file into memory first. No
    # restore actions happen here — we build a flat list of every saved
    # window (for Phase 1) plus a per-workspace structure (for Phase 2),
    # keeping workspace order as it appeared in the file. Each workspace's
    # actual layout (which may differ per-workspace via a workspace rule)
    # is read from its own "wslayout:" line rather than assumed globally. ===
    local loop_ws=""
    local loop_master=""
    local loop_layout=""
    declare -a loop_slaves
    declare -a loop_windows
    declare -a all_entries=()      # each "ws_id|address:class[:...]"
    declare -a ws_order=()         # workspace ids, in saved order
    declare -A ws_layout_map       # ws_id -> layout ("master", "dwindle", ...)
    declare -A ws_master_map       # ws_id -> "address:class" (master mode)
    declare -A ws_slaves_map       # ws_id -> newline-joined slave entries
    declare -A ws_windows_map      # ws_id -> newline-joined window entries

    while IFS= read -r line; do
        if [[ "$line" == current_workspace:* ]] || [[ "$line" == default_layout:* ]]; then
            continue
        elif [[ "$line" == workspace:* ]]; then
            loop_ws="${line#workspace:}"
            loop_master=""
            loop_layout=""
            loop_slaves=()
            loop_windows=()
        elif [[ "$line" == wslayout:* ]]; then
            loop_layout="${line#wslayout:}"
        elif [[ "$line" == master:* ]]; then
            loop_master="${line#master:}"          # "address:class"
        elif [[ "$line" == slave:* ]]; then
            loop_slaves+=("${line#slave:}")          # "address:class"
        elif [[ "$line" == window:* ]]; then
            loop_windows+=("${line#window:}")        # "address:class:atx:aty:w:h"
        elif [[ "$line" == "---" ]]; then
            if [ -n "$loop_ws" ] && [ -n "$loop_master" ]; then
                all_entries+=("${loop_ws}|${loop_master}")
            fi
            for e in "${loop_slaves[@]}"; do
                all_entries+=("${loop_ws}|${e}")
            done
            for e in "${loop_windows[@]}"; do
                all_entries+=("${loop_ws}|${e}")
            done

            if [ -n "$loop_ws" ]; then
                ws_order+=("$loop_ws")
                ws_layout_map["$loop_ws"]="${loop_layout:-$default_layout}"
                ws_master_map["$loop_ws"]="$loop_master"
                ws_slaves_map["$loop_ws"]=$(printf '%s\n' "${loop_slaves[@]}")
                ws_windows_map["$loop_ws"]=$(printf '%s\n' "${loop_windows[@]}")
            fi
            loop_ws=""
            loop_master=""
            loop_layout=""
            loop_slaves=()
            loop_windows=()
        fi
    done < "$STATE_FILE"

    # === Phase 1: move every saved window to its correct workspace first,
    # globally, before any per-workspace ordering runs. This decouples
    # "is everyone where they belong" from "what order are they in", so a
    # workspace's ordering logic never runs while a window meant for it is
    # still elsewhere (or vice versa). ===
    echo "Phase 1: moving all windows to their correct workspaces..."
    for rec in "${all_entries[@]}"; do
        local rec_ws="${rec%%|*}"
        local rec_rest="${rec#*|}"          # "address:class[:...]"
        local rec_addr="${rec_rest%%:*}"
        local rec_class=$(extract_class "$rec_rest")

        local sel
        sel=$(resolve_selector "$rec_addr" "$rec_class") || sel=""
        if [ -z "$sel" ]; then
            echo "  Skipping $rec_class (not currently open, or ambiguous duplicates)"
            continue
        fi

        local cur_ws
        cur_ws=$(resolve_current_client "$rec_addr" "$rec_class" | jq -r '.workspace.id // empty')
        if [ -n "$cur_ws" ] && [ "$cur_ws" != "$rec_ws" ]; then
            echo "  Moving $rec_class from ws $cur_ws to ws $rec_ws"
            hyprctl dispatch "hl.dsp.window.move({ workspace = $rec_ws, window = \"$sel\", follow = false })" 2>/dev/null
            sleep 0.2
        fi
    done

    # === Phase 2: now that everyone's on the right workspace, go workspace
    # by workspace and apply the layout-specific ordering (master
    # promotion + slot order, or dwindle tree rebuild + grid correction). ===
    echo "Phase 2: restoring layout order per workspace..."
    for ws_id in "${ws_order[@]}"; do
        local this_layout="${ws_layout_map[$ws_id]}"
        if [ "$this_layout" = "master" ]; then
            local this_master="${ws_master_map[$ws_id]}"
            if [ -n "$this_master" ]; then
                declare -a these_slaves=()
                while IFS= read -r l; do
                    [ -n "$l" ] && these_slaves+=("$l")
                done <<< "${ws_slaves_map[$ws_id]}"
                restore_workspace_master "$ws_id" "$this_master" these_slaves
            fi
        else
            declare -a these_windows=()
            while IFS= read -r l; do
                [ -n "$l" ] && these_windows+=("$l")
            done <<< "${ws_windows_map[$ws_id]}"
            restore_workspace_dwindle "$ws_id" these_windows
        fi
    done

    # Settle pass: some apps (e.g. launched with a hidden/delayed-start
    # flag) create their real window after Phase 1 has already moved on,
    # and it lands on whatever workspace happens to be active at that
    # later moment instead of the intended one. Re-check every saved
    # window's actual workspace a few times over ~1.5s and correct any
    # stragglers.
    echo "Verifying window placement..."
    for attempt in 1 2 3; do
        local corrected=0
        for rec in "${all_entries[@]}"; do
            local rec_ws="${rec%%|*}"
            local rec_rest="${rec#*|}"          # "address:class[:...]"
            local rec_addr="${rec_rest%%:*}"
            local rec_class=$(extract_class "$rec_rest")

            local cur_ws
            cur_ws=$(resolve_current_client "$rec_addr" "$rec_class" | jq -r '.workspace.id // empty')

            if [ -n "$cur_ws" ] && [ "$cur_ws" != "$rec_ws" ]; then
                local sel
                sel=$(resolve_selector "$rec_addr" "$rec_class") || sel=""
                if [ -n "$sel" ]; then
                    echo "  Correcting $rec_class: ws $cur_ws -> ws $rec_ws"
                    hyprctl dispatch "hl.dsp.window.move({ workspace = $rec_ws, window = \"$sel\", follow = false })" 2>/dev/null
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