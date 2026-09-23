#!/usr/bin/env bash

# find_base_svg <iconName> — echoes the path of the matching base SVG,
# preferring per-game icons over the shared pool. Returns 1 if none exists.
find_base_svg() {
    local name="$1"
    if [ -f "$gameIconsDir/${name}_base_icon.svg" ]; then
        echo "$gameIconsDir/${name}_base_icon.svg"
    elif [ -f "$iconsDir/${name}_base_icon.svg" ]; then
        echo "$iconsDir/${name}_base_icon.svg"
    else
        return 1
    fi
}

# colorize_svg <src> <dst> <iconName>
# Recolors according to colorTokens (default: replace currentColor).
patch_svg_color() {
    local src="$1" dst="$2" name="$3"
    local tokens="${colorTokens[$name]:-currentColor}"

    if [ "$tokens" = "@inject" ]; then
        # Icon has no explicit fill anywhere — inject one on the root svg
        # tag. "0,/<svg/" (GNU sed) matches only the first occurrence in
        # the whole file, not just the first line, same as Python's
        # re.sub(..., count=1) this replaced.
        sed "0,/<svg/{s//<svg fill=\"$accent\"/}" "$src" > "$dst"
    else
        # Space-separated token list (usually just "currentColor") — one
        # -e per token, all applied in a single sed invocation. "|" as
        # delimiter avoids collision with "/" that can appear in SVG path
        # data if a token pattern ever needs to be that specific.
        local sedArgs=()
        for token in $tokens; do
            sedArgs+=(-e "s|$token|$accent|g")
        done
        sed "${sedArgs[@]}" "$src" > "$dst"
    fi
}

# ensure_icon <iconName> — generates the accent-colored SVG in the theme
# dir exactly once per run. Returns 1 if no base SVG exists for the name.
ensure_icon() {
    local name="$1" src
    [ -n "${generatedIcons[$name]:-}" ] && return 0
    src=$(find_base_svg "$name") || return 1
    patch_svg_color "$src" "$iconThemeDir/apps/scalable/$name.svg" "$name"
    generatedIcons[$name]=1
}

cleanup_icon_cache() {
    rm -f "$HOME/.cache/icon-cache.kcache"
    kbuildsycoca6 --noincremental 2>/dev/null
}

# time_step <label> <command...> — runs the given command, prints its
# wall-clock time to stderr afterward. awk instead of bc for the float
# subtraction so this doesn't need an extra package installed. Works for
# both function calls and plain external commands (e.g. the
# TrayIconPatcher.sh invocation and update-desktop-database below).
time_step() {
    local label="$1"; shift
    local start end
    start=$(date +%s.%N)
    "$@"
    end=$(date +%s.%N)
    awk -v s="$start" -v e="$end" -v l="$label" \
        'BEGIN { printf "[TIMING] [%7.3fs] %s\n", e - s, l }' >&2
}

# Same contract as time_step, but backgrounds the command and prefixes
# every line it prints (stdout AND stderr, merged) with "[label] ".
# Output is captured to a temp file rather than piped live through sed —
# see TrayIconPatcher.sh's time_step_bg for why: a live pipe can be held
# open by any backgrounded+disowned grandchild that doesn't redirect its
# own output away first, blocking this whole job from ever finishing even
# though the wrapped command itself already returned. A regular file has
# no such blocking semantics. Never wrap this in $(...) to grab the PID —
# see TrayIconPatcher.sh's time_step_bg for why that reparents the job
# away from this script's job table.
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
            'BEGIN { printf "[TIMING] [%7.3fs] %s\n", e - s, l }' >&2
        exit $rc
    ) &
}