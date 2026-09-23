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
supportScriptsDir="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/hyprLayoutPreservationSupportScripts"

# Scratch workspace used to "evict" windows (dwindle/scrolling/monocle) so
# their internal position is forgotten before being reinserted in order.
dwindleScratchWorkspace="special:layoutscratch"

#----------------------------------------------------- Utilities -----------------------------------------------------

get_layout_mode() {
    hyprctl getoption general:layout -j | jq -r '.str'
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

#---------------------------------------------------------------------------------------------------------------------

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

source "$supportScriptsDir/DwindleLayoutWorkspaceRestorer.sh"
source "$supportScriptsDir/MasterLayoutWorkspaceRestorer.sh"
source "$supportScriptsDir/MonocleLayoutWorkspaceRestorer.sh"
source "$supportScriptsDir/ScrollingLayoutWorkspaceRestorer.sh"

case "$1" in
    save)    save_layout ;;
    restore) restore_layout ;;
    *)
        echo "Usage: $0 save|restore"
        exit 1
        ;;
esac