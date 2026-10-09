#!/usr/bin/env bash
# ThemeRefresher.sh
# Entry point for the whole theming pipeline. Picks an accent color from
# the wallpaper, then fans out to every per-app/per-subsystem patcher
# (RGB, KDE, GTK, browsers, mail, Discord, icons, VS Code, SourceGit,
# ...), restarts the apps it just patched, and restores window layout.
#
# --full order: save layout -> pick color -> STOP apps (in the background) ->
# run patchers while the apps shut down -> relaunch apps -> wait for their
# windows -> restore layout. Stopping first hides the shutdown time behind the
# patchers, and means app configs are patched while the app is closed, so an
# app can't overwrite them on exit.
#
# Usage: ThemeRefresher.sh --full|--rgb|--softrun|--tray|--help

supportDir="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"

# Runs "$@", prints its wall-clock time to stderr as "[timing] label: Ns".
# Timing goes to stderr so `color=$(time_step ColorChooser ...)` still only
# captures the wrapped command's real stdout.
time_step() {
    local label="$1"; shift
    local startTime endTime elapsed rc
    startTime=$(date +%s%N)
    "$@"
    rc=$?
    endTime=$(date +%s%N)
    elapsed=$(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
    echo "[timing] ${label}: ${elapsed}s" >&2
    return $rc
}

# Same contract as time_step, but backgrounds "$@" instead of waiting for
# it. Callers fire-and-collect $! themselves; the timing line still prints
# once the job finishes (from inside the subshell).
#
# Every line "$@" prints (stdout+stderr merged) is prefixed "[label] ".
# Output is captured to a temp file rather than piped live through sed:
# a wrapped script that itself backgrounds+disowns work (RgbApply.sh's
# ratbagctl loop does this) inherits this job's stdout/stderr fd. Piped
# through sed, that disowned grandchild would hold the pipe open until IT
# finishes too — even though the wrapped script already returned — so
# `wait` would block on unrelated background work. A regular file has no
# such blocking semantics. Trade-off: output only appears (all at once,
# labeled) once the wrapped command's own script portion finishes.
#
# IMPORTANT: never wrap this in $(...) to grab the PID — command
# substitution runs in its own subshell, so a job backgrounded inside it
# gets reparented away (not a child of this script) once that subshell
# exits, and `wait $pid` from here would silently fail to wait for it.
# Call directly, then read $! right after:
#   time_step_bg "label" some_cmd args...
#   myPids+=("$!")
time_step_bg() {
    local label="$1"; shift
    local outFile
    outFile=$(mktemp)
    (
        local startTime endTime elapsed rc
        startTime=$(date +%s%N)
        "$@" > "$outFile" 2>&1
        rc=$?
        endTime=$(date +%s%N)
        sed "s/^/[$label] /" "$outFile"
        rm -f "$outFile"
        elapsed=$(awk -v a="$startTime" -v b="$endTime" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
        echo "[timing] ${label}: ${elapsed}s" >&2
        exit $rc
    ) &
}

usage() {
    cat << EOF
Usage: ./ThemeRefresher.sh [OPTION]

Options:
  --full             Run the full theme refresh process (including restarting apps)
  --rgb              Apply the accent color to RGB devices only
  --softrun          Apply the accent color to RGB devices, patch themes and icons, but do not restart any apps
  --tray             Run the tray icon updater only
  --help             Show this help message
EOF
}

# Blocks until a NEW window of each given Hyprland class appears (or the
# shared 5s deadline is hit). Used so HyprLayoutPreservation.sh's restore
# only runs once every relaunched window actually exists — otherwise a
# late-appearing window (e.g. Spotify) grabs focus after restore already
# set it. Every app shares one deadline and is checked every tick, so one
# slow app no longer blocks the ones behind it, and each tick costs one
# `hyprctl clients -j` + `jq` call total.
#
# "New" = its address wasn't in $preRestartAddrs (snapshot taken right
# before the relaunch), so a just-killed window that Hyprland hasn't
# dropped yet can't be mistaken for the relaunched one.
#   $1 (nameref) - array of "app|class" entries to wait for
wait_for_hypr_classes() {
    local -n pending="$1"
    local deadline=$(( SECONDS + 5 ))
    local startTime=${EPOCHREALTIME/,/.}

    while [ ${#pending[@]} -gt 0 ] && [ "$SECONDS" -lt "$deadline" ]; do
        local openClasses
        openClasses=$(hyprctl clients -j | jq -r --arg old "$preRestartAddrs" \
            '($old | split("\n")) as $o | .[] | select(.address as $a | ($o | index($a)) == null) | .class | ascii_downcase')
        local -a stillPending=()
        for entry in "${pending[@]}"; do
            local app="${entry%%|*}"
            local windowClass="${entry#*|}"
            if [[ "$openClasses" == *"${windowClass,,}"* ]]; then
                echo "[timing] wait_for_hypr_class(${app}): $(awk -v a="$startTime" -v b="${EPOCHREALTIME/,/.}" 'BEGIN{printf "%.3f", b-a}')s" >&2
            else
                stillPending+=("$entry")
            fi
        done
        pending=("${stillPending[@]}")
        [ ${#pending[@]} -gt 0 ] && sleep 0.03
    done

    # Anything left never appeared within the shared deadline — still emit
    # a timing line for it.
    if [ ${#pending[@]} -gt 0 ]; then
        local elapsed
        elapsed=$(awk -v a="$startTime" -v b="${EPOCHREALTIME/,/.}" 'BEGIN{printf "%.3f", b-a}')
        for entry in "${pending[@]}"; do
            echo "[timing] wait_for_hypr_class(${entry%%|*}): ${elapsed}s" >&2
        done
    fi
}

# Group A: patchers that only need the raw hex color, write to a file
# tree none of the others touch, and never read anything matugen renders
# — safe to launch fully concurrently with each other and with matugen.
# Group B: patchers that need matugen's rendered output (IconPatcher and
# VscodePatcher degrade gracefully to the raw seed if it's missing;
# SourceGitPatcher hard-requires it) — wait for matugen, but not Group A.
run_patchers() {
    local color="$1"
    declare -a patcherPids=()

    time_step_bg "RgbApply" "$supportDir/RgbApply.sh" "$color"
    patcherPids+=("$!")
    time_step_bg "KdePatcher" "$supportDir/KdePatcher.sh" "$color"
    patcherPids+=("$!")
    time_step_bg "GtkPatcher" "$supportDir/GtkPatcher.sh" "$color"
    patcherPids+=("$!")
    if command -v ferdium >/dev/null 2>&1; then
        time_step_bg "FerdiumPatcher" "$supportDir/appPatchers/FerdiumPatcher.sh" "$color"
        patcherPids+=("$!")
        time_step_bg "FerdiumIconPatcher" "$supportDir/appPatchers/FerdiumIconPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v vesktop >/dev/null 2>&1; then
        time_step_bg "DiscordPatcher" "$supportDir/appPatchers/DiscordPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v zen-browser >/dev/null 2>&1; then
        time_step_bg "ZenPatcher" "$supportDir/appPatchers/ZenPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v firefox >/dev/null 2>&1; then
        time_step_bg "FirefoxPatcher" "$supportDir/appPatchers/FirefoxPatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v betterbird >/dev/null 2>&1 || command -v thunderbird >/dev/null 2>&1; then
        time_step_bg "ThunderbirdPatcher" "$supportDir/appPatchers/ThunderbirdPatcher.sh" "$color"
        patcherPids+=("$!")
    fi

    # matugen, launched alongside Group A — nothing in Group A reads its output.
    time_step_bg "matugen" matugen color hex "#$color" --quiet
    local matugenPid=$!

    wait "$matugenPid"

    time_step_bg "IconPatcher" "$supportDir/IconPatcher.sh" "$color"
    patcherPids+=("$!")
    if command -v sonora >/dev/null 2>&1; then
        time_step_bg "SonoraPatcher" "$supportDir/appPatchers/SonoraPatcher.sh"
        patcherPids+=("$!")
    fi
    if command -v code >/dev/null 2>&1; then
        time_step_bg "VscodePatcher" "$supportDir/appPatchers/VscodePatcher.sh" "$color"
        patcherPids+=("$!")
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        time_step_bg "SourceGitPatcher" "$supportDir/appPatchers/SourceGitPatcher.sh" "$color"
        patcherPids+=("$!")
    fi

    for pid in "${patcherPids[@]}"; do
        wait "$pid"
    done
}

# EXIT trap for cmd_full. The apps are closed for the whole patcher phase now,
# so if the script is interrupted (Ctrl-C, a crash) between stopping and
# relaunching them, bring them back instead of leaving them closed.
restore_apps_on_abort() {
    if [ "${appsStopped:-0}" = 1 ] && [ "${appsStarted:-0}" != 1 ]; then
        echo "Interrupted: relaunching the apps that were stopped" >&2
        app_stop_wait
        app_start_all
    fi
}

cmd_full() {
    # Save Hyprland layout state before any app is stopped. Backgrounded: it
    # touches neither color nor any theme file, so ColorChooser doesn't need
    # to wait on it — it only needs to finish before the apps are stopped,
    # below, so it gets ColorChooser's whole runtime for free.
    hyprSavePid=""
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        time_step_bg "HyprLayoutPreservation save" "$supportDir/HyprLayoutPreservation.sh" save
        hyprSavePid=$!
    fi

    # Choosing the color is genuinely serial — every patcher below needs it.
    # Nothing has been stopped yet, so aborting here leaves everything running.
    color=$(time_step "ColorChooser" "$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Format: pgrepFlag|detectPattern|killPattern|launchCmd|hyprlandWindowClass|gracePeriod
    # An empty class means "don't wait for its window"; a grace of 0 means
    # SIGKILL right away (code and vesktop were being SIGKILLed after the full
    # grace anyway, so 0 only skips the wait).
    declare -A apps
    apps[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
    apps[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|ferdium"
    apps[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"
    apps[gitcomet]="x|gitcomet|gitcomet|gitcomet|gitcomet"
    apps[code]="x|code|code|code|com.microsoft.VSCode|0"
    apps[vesktop]="x|vesktop|vesktop|vesktop -m||0"
    apps[localsend]="x|localsend|localsend|localsend --hidden|"
    apps[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird"
    apps[thunderbird]="f|thunderbird|thunderbird|thunderbird|org.mozilla.Thunderbird"
    apps[swaync]="x|swaync|swaync|swaync"

    source "$supportDir/AppRestarter.sh"

    # The layout save must be finished before any window disappears.
    [ -n "$hyprSavePid" ] && wait "$hyprSavePid"

    # STOP PHASE: start closing every running app now. They shut down in the
    # background while the patchers below run, instead of after them.
    appsStopped=1
    appsStarted=0
    trap restore_apps_on_abort EXIT
    app_stop_begin

    # Every patcher must be fully finished before the apps are relaunched
    # (below) — a relaunch racing an in-flight patcher could load a
    # half-written or stale config. Concurrent jobs' own stdout/stderr
    # interleave line-by-line above; accepted tradeoff of running them in
    # parallel.
    run_patchers "$color"

    # Sonora is only restarted when its settings.json differs from the freshly
    # rendered palette, which isn't known until matugen has run — so it is
    # stopped late, here, instead of with the rest.
    if command -v sonora >/dev/null 2>&1 \
        && "$supportDir/appPatchers/SonoraPatcher.sh" --pending; then
        sonoraPatcher="$supportDir/appPatchers/SonoraPatcher.sh"
        # Must be read now: stopping Sonora is about to kill the window.
        export SONORA_WINDOW_STATE
        SONORA_WINDOW_STATE=$("$sonoraPatcher" --window-state)
        # A tray-only Sonora gets its window closed again right after launch,
        # so don't make wait_for_hypr_classes wait for it.
        sonoraClass="sonora"
        [ "$SONORA_WINDOW_STATE" = "hidden" ] && sonoraClass=""
        apps[sonora]="x|sonora|sonora|$sonoraPatcher --launch|$sonoraClass"
        app_stop_begin sonora
    fi

    #Nativmix restart using built-in restart flag
    if command -v nativmix >/dev/null 2>&1 && pgrep -f "nativmix" >/dev/null 2>&1; then
        echo "nativmix running"
        nativmix --restart --hidden &
    fi

    # Every stop must have finished before anything is relaunched.
    app_stop_wait

    # Snapshot of the windows that exist right before the relaunch, so
    # wait_for_hypr_classes only counts windows created after it.
    preRestartAddrs=""
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        preRestartAddrs=$(hyprctl clients -j | jq -r '.[].address')
    fi

    # START PHASE
    time_step "app start" app_start_all
    appsStarted=1

    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        declare -a hyprPending=()
        for app in "${running[@]}"; do
            IFS='|' read -r _ _ _ _ windowClass _ <<< "${apps[$app]}"
            [ -z "$windowClass" ] && continue
            echo "Waiting for $app to appear..."
            hyprPending+=("${app}|${windowClass}")
        done
        [ ${#hyprPending[@]} -gt 0 ] && wait_for_hypr_classes hyprPending
    fi

    # Desktop-environment-specific actions
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        # Restore Hyprland layout state after all restarts (Spotify included)
        time_step "HyprLayoutPreservation restore" "$supportDir/HyprLayoutPreservation.sh" restore
        time_step "waybar restart" systemctl --user restart waybar.service
    elif [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    fi
}

cmd_rgb() {
    color=$("$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    "$supportDir/RgbApply.sh" "$color"
}

cmd_softrun() {
    color=$(time_step "ColorChooser" "$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Wait for every patcher before restarting plasmashell/waybar below —
    # otherwise the restart could happen before some configs are written.
    run_patchers "$color"

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        time_step "waybar restart" systemctl --user restart waybar.service
    fi
}

cmd_tray() {
    color=$(time_step "ColorChooser" "$supportDir/ColorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: ColorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    time_step "TrayIconPatcher.sh" "$supportDir/TrayIconPatcher.sh" "$color"

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        time_step "waybar restart" systemctl --user restart waybar.service
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