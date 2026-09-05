#!/usr/bin/env bash
# Utils.sh
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

# ---------------------------------------------------------------------------
# multiselect: pure-bash arrow-key + spacebar multi-select menu.
# $1 = name of array to write results into (by reference)
# $2 = name of array holding the options (pass as arrayname[@])
# $3 = optional name of array holding "locked" option values (pass as
#      arrayname[@]) — these are pre-selected and cannot be toggled off,
#      shown with a "(required)" tag.
# ---------------------------------------------------------------------------
multiselect() {
    local -n result=$1
    local options=("${!2}")
    local locked=()
    if [ -n "${3:-}" ]; then
        locked=("${!3}")
    fi
    local selected=()
    local cursor=0
    local count=${#options[@]}

    is_locked() {
        local item="$1"
        local l
        for l in "${locked[@]}"; do
            [ "$item" = "$l" ] && return 0
        done
        return 1
    }

    for ((i = 0; i < count; i++)); do
        if is_locked "${options[i]}"; then
            selected[i]=1
        else
            selected[i]=0
        fi
    done

    tput civis

    while true; do
        for ((i = 0; i < count; i++)); do
            if [ "$i" -eq "$cursor" ]; then
                printf "\033[7m"
            fi
            local tag=""
            is_locked "${options[i]}" && tag=" (required)"
            if [ "${selected[i]}" -eq 1 ]; then
                printf " [x] %s%s \033[0m\n" "${options[i]}" "$tag"
            else
                printf " [ ] %s%s \033[0m\n" "${options[i]}" "$tag"
            fi
        done

        IFS= read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            case "$key" in
                '[A')
                    ((cursor--))
                    [ "$cursor" -lt 0 ] && cursor=$((count - 1))
                    ;;
                '[B')
                    ((cursor++))
                    [ "$cursor" -ge "$count" ] && cursor=0
                    ;;
            esac
        elif [[ $key == "" ]]; then
            break
        elif [[ $key == " " ]]; then
            if ! is_locked "${options[cursor]}"; then
                if [ "${selected[cursor]}" -eq 1 ]; then
                    selected[cursor]=0
                else
                    selected[cursor]=1
                fi
            fi
        fi

        printf "\033[%dA" "$count"
    done

    tput cnorm

    result=()
    for ((i = 0; i < count; i++)); do
        if [ "${selected[i]}" -eq 1 ]; then
            result+=("${options[i]}")
        fi
    done
}