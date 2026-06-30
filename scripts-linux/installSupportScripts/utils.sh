#!/usr/bin/env bash
# utils.sh
# Shared utility functions for install scripts.
# Meant to be SOURCED, not executed.

# Draws a visual progress bar by parsing rsync's --info=progress2 output.
# --no-inc-recursive forces rsync to scan all files first so the percentage
# is accurate and never goes backwards.
# Usage: copy_with_bar "Label..." <rsync sources...> <destination>
copy_with_bar() {
    local label="$1"
    shift
    echo "$label"

    rsync -a --no-inc-recursive --info=progress2 "$@" 2>&1 | \
    while IFS= read -d $'\r' -r line; do
        pct=$(echo "$line" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
        [ -z "$pct" ] && continue
        xfr=$(echo "$line" | grep -oE 'xfr#[0-9]+' | grep -oE '[0-9]+')
        total=$(echo "$line" | grep -oE 'to-chk=[0-9]+/[0-9]+' | grep -oE '/[0-9]+' | tr -d '/')
        local filled=$(( pct * 40 / 100 ))
        local empty=$(( 40 - filled ))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        if [ -n "$xfr" ] && [ -n "$total" ]; then
            printf "\r  [%s] %3d%%  (%s/%s files)" "$bar" "$pct" "$xfr" "$total"
        else
            printf "\r  [%s] %3d%%" "$bar" "$pct"
        fi
    done
    printf "\n"
}
