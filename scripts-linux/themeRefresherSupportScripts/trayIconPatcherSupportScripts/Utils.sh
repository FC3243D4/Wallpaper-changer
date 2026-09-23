#!/usr/bin/env bash

# Shared helper — always recolors fresh from the base SVG using this
# script's own (waybar-corrected) $accent. Deliberately does NOT reuse
# $iconThemeDir/apps/scalable/<name>.svg even when it exists, since that
# copy was colored by IconPatcher.sh's engine with the raw wallpaper seed
# — reusing it would silently defeat the primary correction above. Costs
# a redundant recolor, but guarantees tray icons and waybar text agree.
resolve_themed_svg() {
    local name="$1"
    local base=""
    [ -f "$gameIconsDir/${name}_base_icon.svg" ] && base="$gameIconsDir/${name}_base_icon.svg"
    [ -z "$base" ] && [ -f "$iconsDir/${name}_base_icon.svg" ] && base="$iconsDir/${name}_base_icon.svg"
    [ -z "$base" ] && return 1

    local tmp
    tmp=$(mktemp --suffix=.svg)
    sed "s/currentColor/$accent/g" "$base" > "$tmp"
    echo "$tmp"
}

# fix_system_dir_permissions <dir> <label>
# One-time chown of a package-owned directory to the current user, so
# subsequent writes need no sudo at all — until the next package update
# resets ownership back to root, at which point this just redoes it.
# Non-blocking: uses `sudo -n`, so it fails fast instead of hanging when
# there's no cached credential/interactive terminal (see: the hang bug
# from an earlier version of this pattern). Ownership is otherwise kept
# in sync by TARGETS in update-and-fix.sh, which runs after every
# topgrade and re-chowns anything a package update reset to root.
fix_system_dir_permissions() {
    local dir="$1" label="$2"
    [ -w "$dir" ] && return 0
    echo "  $label: $dir is root-owned, attempting one-time chown..."
    if sudo -n chown -R "$USER" "$dir" 2>/dev/null; then
        echo "  $label: ownership fixed — future runs won't need sudo."
        echo "  (if theming silently stops updating after a $label package"
        echo "   update, that's this directory getting reset to root again — just"
        echo "   re-run this script and it'll redo the chown.)"
        return 0
    fi
    echo "  $label: couldn't chown automatically (needs an interactive sudo prompt)."
    echo "  Run this once yourself, then re-run this script:"
    echo "    sudo chown -R \$USER $dir"
    return 1
}

# time_step_bg <label> <function> — same contract as time_step, but
# backgrounds the function and prefixes every line it prints (stdout+
# stderr merged) with "[label] " so concurrent jobs' output stays
# attributable (same technique ThemeRefresher.sh's time_step_bg uses).
#
# Output is captured to a temp file, not piped live through sed: if any
# function here backgrounds+disowns work of its own without redirecting
# that work's output first (e.g. force_ytm_desktop_reload's 12s delayed
# revert — already safely redirected, but exactly the risky shape), a
# live pipe would let that orphaned writer hold the pipe open
# indefinitely, turning a fast step into a stuck one. A regular file has
# no such blocking semantics — confirmed by reproducing the failure
# against RgbApply.sh's disowned ratbagctl loop elsewhere in this pipeline.
#
# Every function below writes to a different app's own disjoint asset
# directory (blueman is the only one touching $iconThemeDir), and the
# shared helpers they call (resolve_themed_svg, fix_system_dir_permissions)
# are safe under concurrency too — so running them all in parallel is fine.
#
# Never wrap this in $(...) to grab the PID — that runs in its own
# subshell, and a job backgrounded inside it gets reparented away (not a
# waitable child of this script) once the subshell exits. Call directly,
# then read $! right after.
time_step_bg() {
    local label="$1"; shift
    local outfile
    outfile=$(mktemp)
    (
        local start end rc
        start=$(date +%s.%N)
        "$@" > "$outfile" 2>&1
        rc=$?
        end=$(date +%s.%N)
        sed "s/^/[$label] /" "$outfile"
        rm -f "$outfile"
        awk -v s="$start" -v e="$end" -v l="$label" \
            'BEGIN { printf "  [%7.3fs] %s\n", e - s, l }' >&2
        exit $rc
    ) &
}