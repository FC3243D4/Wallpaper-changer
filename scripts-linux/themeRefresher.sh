#!/usr/bin/env bash

SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"

# Runs "$@" and prints how long it took, e.g. "[timing] iconPatcher: 0.842s".
# The timing line goes to stderr, so `color=$(timed colorChooser ...)` still
# only captures the wrapped command's real stdout.
timed() {
    local label="$1"; shift
    local t0 t1 elapsed rc
    t0=$(date +%s%N)
    "$@"
    rc=$?
    t1=$(date +%s%N)
    elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
    echo "[timing] ${label}: ${elapsed}s" >&2
    return $rc
}

# Same contract as timed(), but backgrounds "$@" instead of waiting for it.
# The timing line still prints itself once the job actually finishes
# (from inside the subshell), so callers just fire-and-collect $! —
# there's no return-code/label to relay back separately. Concurrent jobs'
# stdout/stderr WILL interleave line-by-line in the log; that's the
# accepted tradeoff of running them in parallel.
#
# IMPORTANT: never wrap this in $(...) to grab the PID — command
# substitution runs in its own subshell, and a job backgrounded inside
# that subshell gets reparented away (not a child of this script) the
# instant the substitution's subshell exits, so `wait $pid` from here
# would silently fail to wait for it. Call timed_bg directly, then read
# $! immediately after — like this:
#   timed_bg "label" some_cmd args...
#   my_pids+=("$!")
timed_bg() {
    local label="$1"; shift
    (
        local t0 t1 elapsed rc
        t0=$(date +%s%N)
        "$@"
        rc=$?
        t1=$(date +%s%N)
        elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
        echo "[timing] ${label}: ${elapsed}s" >&2
        exit $rc
    ) &
}

usage() {
    cat << EOF
Usage: ./install-Linux.sh [OPTION]

Options:
  --full             Run the full theme refresh process (including restarting apps)
  --rgb              Apply the accent color to RGB devices only
  --softrun          Apply the accent color to RGB devices, patch themes and icons, but do not restart any apps
  --tray             Run the tray icon updater only
  --help             Show this help message
EOF
}

cmd_full() {
    # Save Hyprland layout state before any restarts. Backgrounded: it
    # doesn't touch color or any theme file, so there's no reason for
    # colorChooser to wait on it — it only needs to finish before
    # appRestarter runs, much further down, so it gets this entire
    # pipeline's worth of headroom for free. Waited on right before
    # appRestarter below.
    hypr_save_pid=""
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        timed_bg "hyprLayoutPreservation save" "$SUPPORT/hyprLayoutPreservation.sh" save
        hypr_save_pid=$!
    fi

    # 1. Choose accent color from wallpaper — genuinely serial: every
    # patcher below needs this value, so nothing can start before it.
    color=$(timed "colorChooser" "$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # --- Group A: everything that only needs the raw hex color, writes to
    # a file tree none of the others touch, and never reads anything
    # matugen renders (checked against every script in this repo) — safe
    # to run fully concurrently with each other AND with matugen itself.
    declare -a patcher_pids=()

    timed_bg "rgbApply" "$SUPPORT/rgbApply.sh" "$color"
    patcher_pids+=("$!")
    timed_bg "kdePatcher" "$SUPPORT/kdePatcher.sh" "$color"
    patcher_pids+=("$!")
    timed_bg "gtkPatcher" "$SUPPORT/gtkPatcher.sh" "$color"
    patcher_pids+=("$!")
    if command -v ferdium >/dev/null 2>&1; then
        timed_bg "ferdiumPatcher" "$SUPPORT/appPatchers/ferdiumPatcher.sh" "$color"
        patcher_pids+=("$!")
        timed_bg "ferdiumIconPatcher" "$SUPPORT/appPatchers/ferdiumIconPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    if command -v vesktop >/dev/null 2>&1; then
        timed_bg "discordPatcher" "$SUPPORT/appPatchers/discordPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    #browser patchers
    if command -v zen-browser >/dev/null 2>&1; then
        timed_bg "zenPatcher" "$SUPPORT/appPatchers/zenPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    if command -v firefox >/dev/null 2>&1; then
        timed_bg "firefoxPatcher" "$SUPPORT/appPatchers/firefoxPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    #betterbird patcher
    if command -v betterbird >/dev/null 2>&1 || command -v thunderbird >/dev/null 2>&1; then
        timed_bg "thunderbirdPatcher" "$SUPPORT/appPatchers/thunderbirdPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi

    # matugen, also launched alongside Group A — nothing in Group A reads
    # anything matugen renders, so there's no reason to serialize them.
    timed_bg "matugen" matugen color hex "$accent" --quiet
    matugen_pid=$!

    # --- Group B: iconPatcher/vscodePatcher read matugen's rendered
    # output if present (degrading gracefully to the raw seed color if
    # not — see their own comments), and sourceGitPatcher hard-requires
    # it (exits if the rendered file is missing). All three wait for
    # matugen specifically, but NOT for Group A — disjoint files, so no
    # reason to make them wait on each other either.
    wait "$matugen_pid"

    timed_bg "iconPatcher" "$SUPPORT/iconPatcher.sh" "$color"
    patcher_pids+=("$!")
    if command -v code >/dev/null 2>&1; then
        timed_bg "vscodePatcher" "$SUPPORT/appPatchers/vscodePatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        timed_bg "sourceGitPatcher" "$SUPPORT/appPatchers/sourceGitPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi

    # Every patcher must be fully finished before appRestarter (below)
    # relaunches the apps they theme — a relaunch racing an in-flight
    # patcher could load a half-written or stale config instead of the
    # new theme. Concurrent jobs' own stdout/stderr interleave line-by-line
    # in the log above this point; that's the accepted tradeoff of
    # running them in parallel.
    for pid in "${patcher_pids[@]}"; do
        wait "$pid"
    done


    declare -A APPS
    APPS[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
    APPS[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|ferdium"
    APPS[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"
    APPS[code]="x|code|code|code|code"
    APPS[vesktop]="x|vesktop|vesktop|vesktop -m|"
    APPS[nativmix]="x|nativmix|nativmix|nativmix --hidden --restart|"
    APPS[localsend]="x|localsend|localsend|localsend --hidden|"
    APPS[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird"
    APPS[thunderbird]="f|thunderbird|thunderbird|thunderbird|org.mozilla.Thunderbird"
    APPS[swaync]="x|swaync|swaync|swaync"

    # hyprLayoutPreservation save (backgrounded way above) must be done
    # before appRestarter starts killing/relaunching windows.
    [ -n "$hypr_save_pid" ] && wait "$hypr_save_pid"

    # Sourced directly (not via timed()) because it must set $running in
    # THIS shell for the wait_for_hypr_class loop below to see it.
    _t0=$(date +%s%N)
    source "$SUPPORT/appRestarter.sh"
    _t1=$(date +%s%N)
    echo "[timing] appRestarter: $(awk -v a="$_t0" -v b="$_t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2

    # Blocks until a window of the given Hyprland class appears (or times
    # out). Used so hyprLayoutPreservation.sh restore only runs once every
    # relaunched window actually exists — otherwise a late-appearing window
    # (e.g. Spotify) grabs focus after restore already set it.
    # Waits for every relaunched windowed app's class to appear, all at
    # once, instead of running each app's wait sequentially (which could
    # take up to 5s * N apps in the worst case if several apps are slow to
    # restart). All apps share one 5s deadline starting when this is
    # called, and every app is checked on every tick from the start — a
    # slow app no longer blocks the ones behind it in the list from being
    # checked. Also cuts hyprctl calls from one-per-app-per-tick to one
    # total per tick, since a single `hyprctl clients -j` snapshot already
    # has every app's window state in it.
    #   $1 (nameref) - array of "app|class" entries to wait for
    wait_for_hypr_classes() {
        local -n pending="$1"
        local deadline=$(( $(date +%s) + 5 ))
        local t0=$(date +%s%N)

        while [ ${#pending[@]} -gt 0 ] && [ "$(date +%s)" -lt "$deadline" ]; do
            local clients_json
            clients_json=$(hyprctl clients -j)
            local -a still_pending=()
            for entry in "${pending[@]}"; do
                local app="${entry%%|*}"
                local wclass="${entry#*|}"
                if printf '%s' "$clients_json" | python3 -c "
import json, sys
clients = json.load(sys.stdin)
sys.exit(0 if any('$wclass'.lower() in c.get('class', '').lower() for c in clients) else 1)
" 2>/dev/null; then
                    local t1=$(date +%s%N)
                    local elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
                    echo "[timing] wait_for_hypr_class(${app}): ${elapsed}s" >&2
                else
                    still_pending+=("$entry")
                fi
            done
            pending=("${still_pending[@]}")
            [ ${#pending[@]} -gt 0 ] && sleep 0.1
        done

        # Anything left never appeared within the shared deadline — still
        # emit a timing line for it, same as the old timed() wrapper did
        # unconditionally regardless of success or timeout.
        if [ ${#pending[@]} -gt 0 ]; then
            local t1=$(date +%s%N)
            local elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
            for entry in "${pending[@]}"; do
                echo "[timing] wait_for_hypr_class(${entry%%|*}): ${elapsed}s" >&2
            done
        fi
    }

    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        declare -a hypr_pending=()
        for app in "${running[@]}"; do
            IFS='|' read -r _ _ _ _ wclass <<< "${APPS[$app]}"
            [ -z "$wclass" ] && continue
            echo "Waiting for $app to appear..."
            hypr_pending+=("${app}|${wclass}")
        done
        [ ${#hypr_pending[@]} -gt 0 ] && wait_for_hypr_classes hypr_pending
    fi

    #Desktop Environment specific actions
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        # Restore Hyprland layout state after all restarts (Spotify included)
        timed "hyprLayoutPreservation restore" "$SUPPORT/hyprLayoutPreservation.sh" restore

        timed "waybar restart" systemctl --user restart waybar.service

    elif [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    fi
}

cmd_rgb() {
    # 1. Choose accent color from wallpaper
    color=$("$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # 2. Apply to RGB devices (backgrounded — fire and forget)
    "$SUPPORT/rgbApply.sh" "$color"
}

cmd_softrun() {
    # 1. Choose accent color from wallpaper — genuinely serial: every
    # patcher below needs this value, so nothing can start before it.
    color=$(timed "colorChooser" "$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # --- Group A: everything that only needs the raw hex color, writes to
    # a file tree none of the others touch, and never reads anything
    # matugen renders — safe to run fully concurrently with each other
    # and with matugen itself. See cmd_full for the full reasoning.
    declare -a patcher_pids=()

    timed_bg "rgbApply" "$SUPPORT/rgbApply.sh" "$color"
    patcher_pids+=("$!")
    timed_bg "kdePatcher" "$SUPPORT/kdePatcher.sh" "$color"
    patcher_pids+=("$!")
    timed_bg "gtkPatcher" "$SUPPORT/gtkPatcher.sh" "$color"
    patcher_pids+=("$!")
    if command -v ferdium >/dev/null 2>&1; then
        timed_bg "ferdiumPatcher" "$SUPPORT/appPatchers/ferdiumPatcher.sh" "$color"
        patcher_pids+=("$!")
        timed_bg "ferdiumIconPatcher" "$SUPPORT/appPatchers/ferdiumIconPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    if command -v vesktop >/dev/null 2>&1; then
        timed_bg "discordPatcher" "$SUPPORT/appPatchers/discordPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    #browser patchers
    if command -v zen-browser >/dev/null 2>&1; then
        timed_bg "zenPatcher" "$SUPPORT/appPatchers/zenPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    if command -v firefox >/dev/null 2>&1; then
        timed_bg "firefoxPatcher" "$SUPPORT/appPatchers/firefoxPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    #betterbird patcher
    if command -v betterbird >/dev/null 2>&1 || command -v thunderbird >/dev/null 2>&1; then
        timed_bg "thunderbirdPatcher" "$SUPPORT/appPatchers/thunderbirdPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi

    # matugen, also launched alongside Group A.
    timed_bg "matugen" matugen color hex "$accent" --quiet
    matugen_pid=$!

    # --- Group B: needs matugen's rendered output — waits for matugen
    # specifically, but not for Group A. See cmd_full for the reasoning.
    wait "$matugen_pid"

    timed_bg "iconPatcher" "$SUPPORT/iconPatcher.sh" "$color"
    patcher_pids+=("$!")
    if command -v code >/dev/null 2>&1; then
        timed_bg "vscodePatcher" "$SUPPORT/appPatchers/vscodePatcher.sh" "$color"
        patcher_pids+=("$!")
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        timed_bg "sourceGitPatcher" "$SUPPORT/appPatchers/sourceGitPatcher.sh" "$color"
        patcher_pids+=("$!")
    fi

    # Wait for every patcher before restarting plasmashell/waybar below —
    # otherwise the restart could happen before some configs are written.
    for pid in "${patcher_pids[@]}"; do
        wait "$pid"
    done

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        timed "waybar restart" systemctl --user restart waybar.service
    fi
}

cmd_tray() {
    # 1. Choose accent color from wallpaper
    color=$(timed "colorChooser" "$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Run the tray icon updater script
    timed "trayIconPatcher.sh" "$SUPPORT/trayIconPatcher.sh" "$color"

    # Reload shell/waybar to reflect tray icon changes
    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        timed "waybar restart" systemctl --user restart waybar.service
    fi
}

case "$1" in
    --full)        cmd_full ;;
    --rgb)         cmd_rgb ;;
    --softrun)     cmd_softrun ;;
    --tray)        cmd_tray ;;
    --help)        usage ;;
    *)
        if [ -z "$1" ]; then
            echo "No option provided."
        else
            echo "Unknown option: $1"
        fi
        echo ""
        usage
        exit 1
        ;;
esac